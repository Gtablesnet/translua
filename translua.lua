local socket = require("socket")
local io = require("io")
local os = require("os")
local crypto = require("crypto")  -- Include the crypto library for hashing (SHA256)

-- Function to ask for IP and port
function ask_for_ip_and_port(default_ip, default_port)
    print("Enter IP address (default: " .. default_ip .. "):")
    local ip = io.read()
    if ip == "" then ip = default_ip end

    print("Enter port (default: " .. default_port .. "):")
    local port = tonumber(io.read())
    if not port then port = default_port end

    return ip, port
end

-- Function to execute a command on the server (Windows machine)
function execute_command(command)
    local result = ""
    if command:sub(1, 2) == "cd" then
        -- Change directory command (cd)
        local path = command:sub(4)
        local cd_result = os.execute("cd " .. path)
        result = "ACK: Changed directory to: " .. path
    elseif command:sub(1, 3) == "dir" then
        -- List directory contents command (dir)
        local handle = io.popen("dir")
        result = handle:read("*a")  -- Read the output of the dir command
        handle:close()
        result = "ACK: Directory listing:\n" .. result
    elseif command:sub(1, 3) == "get" then
        -- Get file content command (get)
        local filename = command:sub(5)
        local file_content = get_file_content(filename)
        if file_content then
            result = "ACK: File content received."
        else
            result = "ERROR: File not found."
        end
    else
        -- For any other command, try to execute it
        local handle = io.popen(command)
        result = handle:read("*a")
        handle:close()
    end
    return result
end

-- Function to get the content of a file
function get_file_content(filename)
    local file = io.open(filename, "r")
    if file then
        local content = file:read("*a")
        file:close()
        return content
    else
        return nil  -- Return nil if the file is not found
    end
end

-- Function to calculate the checksum (SHA256) of a file
function calculate_checksum(filename)
    local file = io.open(filename, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return crypto.digest("sha256", content)  -- Return the SHA256 hash of the file content
end

-- Function to receive data and execute commands
function server_receive_data(client, chunk_size)
    local command = ""  -- Initialize command variable
    while true do
        -- Try to receive data from client
        local data, err = client:receive(chunk_size)
        if err then
            if err == "closed" then break end
            if err == "timeout" then
                print("Connection timeout, closing the connection.")
                break
            end
            print("Error receiving data:", err)
        elseif data then
            command = command .. data  -- Concatenate received data to the command
            -- If the command ends with a newline, process it
            if command:sub(-1) == "\n" then
                print("Received command:", command)
                local result = execute_command(command)
                client:send(result .. "\n")  -- Send back the result or output of the command
                command = ""  -- Reset the command for the next round
            end
        end
    end
end

-- Main server function that accepts connections and starts the coroutine for receiving data
function server()
    local ip, port = ask_for_ip_and_port("*", 8080)  -- Prompt for IP and port
    local server = assert(socket.bind(ip, port))  -- Bind to specified IP and port
    print("Server started on " .. ip .. ":" .. port .. "... Waiting for a client.")

    while true do
        local client = server:accept()  -- Wait for a client to connect
        client:settimeout(10)  -- Set a timeout for the client connection
        print("Client connected.")

        -- Start the function to handle receiving data and executing commands
        server_receive_data(client, 1024)

        client:close()  -- Close the connection after handling the command
        print("Client disconnected.")
    end
end

server()

-- Function to send a command to the server and receive the result
function client_send_command(client, command)
    client:send(command .. "\n")  -- Send the command to the server

    -- Receive the result of the command from the server
    local result = ""
    while true do
        local chunk, err = client:receive(1024)
        if err then
            if err == "timeout" then
                print("Timeout while waiting for server response.")
                break
            elseif err == "closed" then
                break
            else
                print("Error receiving data:", err)
                break
            end
        end
        result = result .. chunk
        -- Check if the result ends with a newline (indicating the end of the response)
        if result:sub(-1) == "\n" then
            break
        end
    end

    print("Server response:\n", result)

    -- Check if the response contains "ACK" or "ERROR" and handle it
    if result:sub(1, 3) == "ACK" then
        -- If it's an ACK message, proceed with file handling
        if command:sub(1, 3) == "get" then
            local filename = command:sub(5)
            write_file(filename, result)  -- Write the received content to a file
        end
    elseif result:sub(1, 5) == "ERROR" then
        -- If it's an error message, print it and do not write to the file
        print("Error: " .. result)
    end
end

-- Function to write the received content to a file
function write_file(filename, content)
    local file = io.open(filename, "w")
    if file then
        file:write(content)
        file:close()
        print("File saved as: " .. filename)
    else
        print("Error: Unable to save file.")
    end
end

-- Function to verify the integrity of the file by comparing checksums
function verify_file_integrity(filename, expected_checksum)
    local actual_checksum = calculate_checksum(filename)
    if actual_checksum == expected_checksum then
        print("File integrity verified.")
        return true
    else
        print("ERROR: File integrity check failed.")
        return false
    end
end

-- Main client function that connects to the server and sends commands
function client()
    local ip, port = ask_for_ip_and_port("127.0.0.1", 8080)  -- Prompt for IP and port
    local client = assert(socket.tcp())  -- Create a TCP client socket
    client:connect(ip, port)  -- Connect to the server at the specified IP and port
    print("Connected to server.")

    -- Prompt the user to enter commands
    while true do
        print("Enter command (type 'exit' to quit, 'get <filename>' to get a file):")
        local command = io.read()

        if command == "exit" then
            print("Exiting...")
            break
        end

        -- Send command to server and handle response
        client_send_command(client, command)

        -- If the command is 'get', verify the file integrity after download
        if command:sub(1, 3) == "get" then
            local filename = command:sub(5)
            local expected_checksum = calculate_checksum(filename)  -- Get checksum of original file
            if not verify_file_integrity(filename, expected_checksum) then
                print("File transfer failed or corrupted.")
            end
        end
    end

    client:close()  -- Close the connection after sending the commands
    print("Disconnected from server.")
end

client()
