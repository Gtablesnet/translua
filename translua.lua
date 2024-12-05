local socket = require("socket")
local lfs = require("lfs")

-- Function to handle the client role
function runClient()
    print("Running as Client.")
    local client = socket.tcp()

    -- Set timeout for client connection (10 seconds)
    client:settimeout(10)

    -- Get server details
    local host, port = getServerDetails()

    -- Connect to the server
    local success, err = client:connect(host, port)
    if not success then
        handleConnectionError(err)
        return
    end
    print("Connected to server:", host, port)

    -- Client communication loop
    while true do
        local command = getClientCommand()
        if command:lower() == "exit" then
            closeConnection(client)
            break
        end

        handleClientCommand(command, client)
    end
end

-- Helper function to get server details
function getServerDetails()
    print("Enter the server IP Address:")
    local host = io.read()
    print("Enter the server port:")
    local port = tonumber(io.read())
    return host, port
end

-- Helper function to handle connection errors
function handleConnectionError(err)
    if err == "timeout" then
        print("Connection timeout. Please check the server and try again.")
    else
        print("Failed to connect to server:", err)
    end
end

-- Helper function to get a command from the client
function getClientCommand()
    print("Enter a command (or type 'exit' to quit):")
    return io.read()
end

-- Helper function to handle client command
function handleClientCommand(command, client)
    -- Send the command to the server
    local success, err = client:send(command .. "\n")
    if not success then
        print("Error sending data: " .. err)
        return
    end

    -- Wait for the server acknowledgment response
    local response = waitForAck(client)
    if response then
        print("Server response:\n" .. response)
        -- Handle based on the command sent
        if command:match("^get%s+(.+)$") then
            saveFileFromResponse(command, client)
        end
        -- Handle acknowledgment validation
        validateServerAck(response)
    end
end

-- Function to wait for acknowledgment from the server
function waitForAck(client)
    local response, err = client:receive("*a")
    if err then
        print("Error receiving response:", err)
        return nil
    end
    return response
end

-- Function to validate the server's acknowledgment response
function validateServerAck(response)
    if response:match("File received successfully") then
        print("File transfer successful!")
    elseif response:match("Error:") then
        print("Error occurred on server: " .. response)
    else
        print("Unexpected response from server: " .. response)
    end
end

-- Function to save the file from the server's response
function saveFileFromResponse(command, client)
    local filePath = command:match("^get%s+(.+)$")
    local filename = filePath:match("([^/\\]+)$")  -- Extract filename

    -- Open the file in write mode
    local file, err = io.open(filename, "wb")
    if not file then
        print("Error saving the file:", err)
        return
    end

    -- Receive and write the file in chunks
    while true do
        local chunk, err = client:receive(1024)  -- Receive in 1KB chunks
        if err then
            print("Error receiving file chunk:", err)
            break
        end
        if chunk == "EOF" then
            break  -- End of file marker
        end
        file:write(chunk)
    end
    file:close()
    print("File saved as " .. filename)
end

-- Function to close the connection
function closeConnection(client)
    print("Closing connection...")
    client:close()
end

-- Function to handle the server role
function runServer()
    print("Running as Server.")
    local host, port = getServerDetailsForServer()

    -- Set up server and bind to specified host and port
    local server = assert(socket.bind(host, port))
    print("Server started on " .. host .. ":" .. port)

    while true do
        print("Waiting for a client to connect...")
        local client = server:accept() -- Accept a client connection
        print("Client connected!")

        -- Communication loop
        handleServerCommunication(client)
        client:close()
        print("Client connection closed.")
    end
end

-- Helper function to get server details (for server)
function getServerDetailsForServer()
    print("Enter the IP address to bind (default: 127.0.0.1):")
    local host = io.read()
    if host == "" then host = "127.0.0.1" end
    print("Enter the port to listen on (default: 69):")
    local port = tonumber(io.read())
    if not port then port = 69 end
    return host, port
end

-- Helper function to handle server communication
function handleServerCommunication(client)
    while true do
        local data, err = client:receive() -- Receive data from client
        if not data then
            print("Client disconnected or error:", err)
            break
        end

        print("Received command:", data)
        -- Process the command and send acknowledgment
        commandHandling(data, client)
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
        sendDirectoryListing(client)
    elseif data:match("^cd%s+(.+)$") then
        changeDirectory(data, client)
    elseif data:match("^get%s+(.+)$") then
        sendFile(data, client)
    else
        client:send("Unknown command: " .. data .. "\n")
    end
end

-- Function to send the directory listing
function sendDirectoryListing(client)
    local cmd = (package.config:sub(1,1) == '\\') and "dir" or "ls"  -- Platform detection
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    client:send(result)
end

-- Function to change directory
function changeDirectory(data, client)
    local dir = data:match("^cd%s+(.+)$")
    local success, msg = lfs.chdir(dir)
    if success then
        client:send("Changed directory to " .. dir .. "\n")
    else
        client:send("Failed to change directory: " .. msg .. "\n")
    end
end

-- Function to send a file to the client
function sendFile(data, client)
    local filePath = data:match("^get%s+(.+)$")
    local fileData = getFile(filePath)
    if fileData then
        local chunk_size = 1024  -- 1 KB chunks
        for i = 1, #fileData, chunk_size do
            local chunk = fileData:sub(i, i + chunk_size - 1)
            client:send(chunk)
        end
        client:send("EOF")  -- End of file marker
        client:send("\n")   -- New line to mark end of transmission
        client:send("File received successfully\n") -- Send acknowledgment
    else
        client:send("Error: File not found\n")
    end
end

-- Function to read file content
function getFile(filePath)
    local file, err = io.open(filePath, "rb")
    if not file then
        print("Failed to open file:", err)
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

-- Main entry point
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
