local socket = require("socket")
local io = require("io")
local os = require("os")
local crypto = require("crypto")  -- Include the crypto library for hashing (SHA256)

-- Constants for chunk size and timeout
local CHUNK_SIZE = 1024
local TIMEOUT = 10  -- Timeout in seconds

-- Function to log messages to a file
function log(message)
    local log_file = io.open("ftplua.txt", "a")  -- Open the log file in append mode
    if log_file then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")  -- Get the current timestamp
        log_file:write("[" .. timestamp .. "] " .. message .. "\n")  -- Write message with timestamp
        log_file:close()  -- Close the file after writing
    else
        print("Error opening log file.")
    end
end

-- Function to ask for IP and port
function ask_for_ip_and_port(default_ip, default_port)
    log("Prompting for IP and port")
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
    log("Executing command: " .. command)
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

-- Function to send a file in chunks
function send_file_in_chunks(client, filename)
    log("Sending file in chunks: " .. filename)
    local file = io.open(filename, "rb")
    if file then
        local chunk
        repeat
            chunk = file:read(CHUNK_SIZE)  -- Read a chunk of the file
            if chunk then
                client:send(chunk)  -- Send the chunk to the client
            end
        until not chunk  -- Continue until the end of the file
        file:close()
        log("File sent: " .. filename)
    else
        client:send("ERROR: File not found.\n")
        log("Error: File not found for transfer.")
    end
end

-- Function to get the content of a file (for small files)
function get_file_content(filename)
    log("Retrieving content of file: " .. filename)
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
    log("Calculating checksum for file: " .. filename)
    local file = io.open(filename, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return crypto.digest("sha256", content)  -- Return the SHA256 hash of the file content
end

-- Function to handle multiple clients with a timeout
function server_receive_data(client, chunk_size)
    local command = ""  -- Initialize command variable
    local timeout = socket.gettime() + TIMEOUT
    client:settimeout(TIMEOUT)  -- Set the timeout for client connections
    while true do
        -- Try to receive data from client
        local data, err = client:receive(chunk_size)
        if err then
            if err == "closed" then break end
            if err == "timeout" then
                log("Connection timeout, closing the connection.")
                print("Connection timeout, closing the connection.")
                break
            end
            log("Error receiving data: " .. err)
            print("Error receiving data:", err)
        elseif data then
            command = command .. data  -- Concatenate received data to the command
            -- If the command ends with a newline, process it
            if command:sub(-1) == "\n" then
                log("Received command: " .. command)
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
    log("Server started on " .. ip .. ":" .. port .. "... Waiting for a client.")
    print("Server started on " .. ip .. ":" .. port .. "... Waiting for a client.")

    while true do
        local client = server:accept()  -- Wait for a client to connect
        log("Client connected.")
        print("Client connected.")

        -- Start the function to handle receiving data and executing commands
        server_receive_data(client, CHUNK_SIZE)

        client:close()  -- Close the connection after handling the command
        log("Client disconnected.")
        print("Client disconnected.")
    end
end

-- Main client function that connects to the server and sends commands
function client()
    local ip, port = ask_for_ip_and_port("127.0.0.1", 8080)  -- Prompt for IP and port
    local client = assert(socket.tcp())  -- Create a TCP client socket
    client:connect(ip, port)  -- Connect to the server at the specified IP and port
    log("Connected to server at " .. ip .. ":" .. port)
    print("Connected to server.")

    -- Prompt the user to enter commands
    while true do
        print("Enter command (type 'exit' to quit, 'get <filename>' to get a file):")
        local command = io.read()

        if command == "exit" then
            log("Exiting client.")
            print("Exiting...")
            break
        end

        -- Send command to server and handle response
        client_send_command(client, command)

        -- If the command is 'get', check file existence and verify integrity
        if command:sub(1, 3) == "get" then
            local filename = command:sub(5)
            if not file_exists(filename) then
                print("Error: File does not exist locally.")
            else
                local expected_checksum = calculate_checksum(filename)  -- Get checksum of original file
                if not verify_file_integrity(filename, expected_checksum) then
                    log("File transfer failed or corrupted for: " .. filename)
                    print("File transfer failed or corrupted.")
                end
            end
        end
    end

    client:close()  -- Close the connection after sending the commands
    log("Disconnected from server.")
    print("Disconnected from server.")
end

-- Function to send a command to the server and receive the result
function client_send_command(client, command)
    log("Sending command: " .. command)
    client:send(command .. "\n")  -- Send the command to the server

    -- Receive the result of the command from the server
    local result = ""
    while true do
        local chunk, err = client:receive(CHUNK_SIZE)
        if err then
            if err == "timeout" then
                log("Timeout while waiting for server response.")
                print("Timeout while waiting for server response.")
                break
            elseif err == "closed" then
                break
            else
                log("Error receiving data: " .. err)
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

    log("Server response:\n" .. result)
    print("Server response:\n", result)

    -- Handle file writing
    if result:sub(1, 3) == "ACK" then
        if command:sub(1, 3) == "get" then
            local filename = command:sub(5)
            write_file(filename, result)
        end
    elseif result:sub(1, 5) == "ERROR" then
        log("Error: " .. result)
        print("Error: " .. result)
    end
end

-- Function to check if a file exists
function file_exists(filename)
    local file = io.open(filename, "r")
    if file then
        file:close()
        return true
    else
        return false
    end
end

-- Function to write the received content to a file
function write_file(filename, content)
    log("Writing content to file: " .. filename)
    local file = io.open(filename, "w")
    if file then
        file:write(content)
        file:close()
        log("File saved as: " .. filename)
        print("File saved as: " .. filename)
    else
        log("Error: Unable to save file.")
        print("Error: Unable to save file.")
    end
end

-- Function to verify file integrity (checksum comparison)
function verify_file_integrity(filename, expected_checksum)
    log("Verifying file integrity for: " .. filename)
    local file_checksum = calculate_checksum(filename)
    if file_checksum == expected_checksum then
        log("File integrity verified for: " .. filename)
        return true
    else
        log("File integrity check failed for: " .. filename)
        return false
    end
end

-- Main decision function: decides whether to run as client or server
function main()
    print("Choose mode (1: Server, 2: Client):")
    local choice = tonumber(io.read())
    if choice == 1 then
        server()  -- Run the server
    elseif choice == 2 then
        client()  -- Run the client
    else
        print("Invalid choice.")
    end
end

-- Call the main function to start the program
main()
