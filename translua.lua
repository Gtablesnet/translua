local socket = require("socket")
local lfs = require("lfs") -- For directory handling

-- Function to handle the client role
function runClient()
    print("Running as Client.")
    local client = socket.tcp()

    -- Set timeout for client connection (10 seconds)
    client:settimeout(10)

    -- Get server details
    print("Enter the server IP Address:")
    local host = io.read()
    print("Enter the server port:")
    local port = tonumber(io.read())

    -- Connect to the server
    local success, err = client:connect(host, port)
    if not success then
        if err == "timeout" then
            print("Connection timeout. Please check the server and try again.")
        else
            print("Failed to connect to server:", err)
        end
        return
    end
    print("Connected to server:", host, port)

    -- Client communication loop
    while true do
        print("Enter a command (or type 'exit' to quit):")
        local command = io.read()

        if command:lower() == "exit" then
            print("Closing connection...")
            client:close()
            break
        end

        -- Send command to server
        client:send(command .. "\n")

        -- Wait for server response
        local response, receive_err = client:receive("*a")
        if response then
            print("Server response:\n" .. response)

            -- Handle saving files if needed (e.g., "get" command)
            if command:match("^get%s+(.+)$") then
                local filePath = command:match("^get%s+(.+)$")
                local filename = filePath:match("([^/\\]+)$")  -- Extract filename
                local file = io.open(filename, "w")
                if file then
                    file:write(response)
                    file:close()
                    print("File saved as " .. filename)
                else
                    print("Error saving the file.")
                end
            end
        else
            print("Error receiving response:", receive_err)
        end
    end
end

-- Function to handle the server role
function runServer()
    print("Running as Server.")
    print("Enter the IP address to bind (default: 127.0.0.1):")
    local host = io.read()
    if host == "" then host = "127.0.0.1" end
    print("Enter the port to listen on (default: 69):")
    local port = tonumber(io.read())
    if not port then port = 69 end

    -- Set up server and bind to specified host and port
    local server = assert(socket.bind(host, port))
    print("Server started on " .. host .. ":" .. port)

    while true do
        print("Waiting for a client to connect...")
        local client = server:accept() -- Accept a client connection
        print("Client connected!")

        -- Communication loop
        while true do
            local data, err = client:receive() -- Receive data from client
            if not data then
                print("Client disconnected or error:", err)
                break
            end

            print("Received:", data)
            -- Call commandHandling with received data and client
            commandHandling(data, client)
        end
        client:close()
        print("Client connection closed.")
    end
end

-- Function to handle client commands
function commandHandling(data, client)
    -- Validate input to prevent command injection (only alphanumeric characters allowed)
    if not data:match("^[a-zA-Z0-9%s]+$") then
        client:send("Invalid command format. Please try again.\n")
        return
    end

    -- Command handling
    if data:match("^dir$") then
        -- List contents of the current directory
        local handle = io.popen("dir")
        local result = handle:read("*a")
        handle:close()
        client:send(result)
    elseif data:match("^cd%s+(.+)$") then
        local dir = data:match("^cd%s+(.+)$")
        if dir == "" then
            client:send("Error: No directory specified.\n")
        else
            local success, msg = lfs.chdir(dir)
            if success then
                -- Send the current working directory after successful `cd`
                local cwd = lfs.currentdir()
                client:send("Changed directory to " .. cwd .. "\n")
            else
                client:send("Error: Unable to change directory: " .. msg .. "\n")
            end
        end
    elseif data:match("^save%s+(.+)$") then
        local content = data:match("^save%s+(.+)$")
        if content then
            local success, err = saveDataToFile(content)
            if success then
                client:send("Data saved successfully.\n")
            else
                client:send("Error: Unable to save data: " .. err .. "\n")
            end
        else
            client:send("Error: Invalid save command or missing data.\n")
        end
    elseif data:match("^get%s+(.+)$") then
        local filePath = data:match("^get%s+(.+)$")
        if filePath then
            local fileData, err = getFile(filePath)
            if fileData then
                -- Send file content in chunks if necessary
                local chunk_size = 1024  -- 1 KB chunks
                for i = 1, #fileData, chunk_size do
                    local chunk = fileData:sub(i, i + chunk_size - 1)
                    client:send(chunk)
                end
                client:send("\n")  -- End of file signal
            else
                client:send("Error: Unable to read file or file does not exist: " .. err .. "\n")
            end
        end
    else
        client:send("Unknown command: " .. data .. "\n")
    end
end

-- Function to save data to a file
function saveDataToFile(data)
    print("Enter a filename to save the data:")
    local filename = io.read()
    local file, err = io.open(filename, "w")
    if not file then
        print("Error saving data:", err)
        return false, err
    end
    file:write(data)
    file:close()
    print("Data saved to file:", filename)
    return true
end

-- Function to read file content
function getFile(filePath)
    local file, err = io.open(filePath, "r")
    if not file then
        print("Failed to open file:", err)
        return nil, err
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Main function to determine role
function main()
    print("Do you want to run as a (1) Client or (2) Server?")
    local choice = tonumber(io.read())

    if choice == 1 then
        runClient()
    elseif choice == 2 then
        runServer()
    else
        print("Invalid choice. Exiting...")
    end
end

main()
