local socket = require("socket")
local lfs = require("lfs")
local md5 = require("md5") 

-- Global variables
local logFile = "ftp_log.txt"

-- Function to log messages
function logMessage(message)
    local file = io.open(logFile, "a")
    file:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message .. "\n")
    file:close()
end

-- Function to handle the client role
function runClient()
    print("Running as Client.")
    logMessage("Client started")
    local client = socket.tcp()

    -- Set timeout for client connection (10 seconds)
    client:settimeout(10)

    -- Get server details
    local host, port = getServerDetails()

    -- Attempt connection with retry mechanism
    local success = attemptConnection(client, host, port, 3)
    if not success then
        handleConnectionError("Connection failed after retries")
        return
    end
    print("Connected to server:", host, port)
    logMessage("Connected to server: " .. host .. ":" .. port)

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

-- Helper function to attempt connection with retries
function attemptConnection(client, host, port, retries)
    local attempt = 0
    while attempt < retries do
        local success, err = client:connect(host, port)
        if success then
            return true
        end
        attempt = attempt + 1
        print("Connection failed. Retrying... (" .. attempt .. "/" .. retries .. ")")
        logMessage("Connection failed. Retrying... (" .. attempt .. "/" .. retries .. ")")
        socket.sleep(2)  -- Wait before retrying
    end
    print("Failed to connect after " .. retries .. " attempts.")
    logMessage("Failed to connect after " .. retries .. " attempts.")
    return false
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
    logMessage("Connection error: " .. err)
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
        logMessage("Error sending command: " .. err)
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
        logMessage("Error receiving response: " .. err)
        return nil
    end
    return response
end

-- Function to validate the server's acknowledgment response
function validateServerAck(response)
    if response:match("File received successfully") then
        print("File transfer successful!")
        logMessage("File transfer successful")
    elseif response:match("Error:") then
        print("Error occurred on server: " .. response)
        logMessage("Server error: " .. response)
    else
        print("Unexpected response from server: " .. response)
        logMessage("Unexpected server response: " .. response)
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
        logMessage("Error saving file: " .. err)
        return
    end

    local totalSize = 0
    local receivedData = ""
    -- Receive and write the file in chunks
    while true do
        local chunk, err = client:receive(1024)  -- Receive in 1KB chunks
        if err then
            print("Error receiving file chunk:", err)
            logMessage("Error receiving file chunk: " .. err)
            break
        end
        if chunk == "EOF" then
            break  -- End of file marker
        end
        file:write(chunk)
        totalSize = totalSize + #chunk
        receivedData = receivedData .. chunk
    end
    file:close()

    -- Verify the file integrity (using MD5 checksum)
    local checksum = md5.sumhexa(receivedData)
    logMessage("File " .. filename .. " received, checksum: " .. checksum)

    print("File saved as " .. filename)
    logMessage("File saved as " .. filename)
end

-- Function to close the connection
function closeConnection(client)
    print("Closing connection...")
    logMessage("Closing connection")
    client:close()
end

-- Function to handle the server role
function runServer()
    print("Running as Server.")
    logMessage("Server started")
    local host, port = getServerDetailsForServer()

    -- Set up server and bind to specified host and port
    local server = assert(socket.bind(host, port))
    print("Server started on " .. host .. ":" .. port)
    logMessage("Server started on " .. host .. ":" .. port)

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
            logMessage("Client disconnected or error: " .. err)
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
        logMessage("Invalid command format received: " .. data)
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
        logMessage("Unknown command received: " .. data)
    end
end

-- Function to send the directory listing
function sendDirectoryListing(client)
    local cmd = (package.config:sub(1,1) == '\\') and "dir" or "ls"  -- Platform detection
    local handle = io.popen(cmd)
    local result = handle:read("*a")
    handle:close()
    client:send(result)
    logMessage("Sent directory listing")
end

-- Function to change directory
function changeDirectory(data, client)
    local dir = data:match("^cd%s+(.+)$")
    local success, msg = lfs.chdir(dir)
    if success then
        client:send("Changed directory to " .. dir .. "\n")
        logMessage("Changed directory to " .. dir)
    else
        client:send("Error changing directory: " .. msg .. "\n")
        logMessage("Error changing directory: " .. msg)
    end
end

-- Function to send the file
function sendFile(data, client)
    local filePath = data:match("^get%s+(.+)$")
    local file = io.open(filePath, "rb")
    if not file then
        client:send("Error: File not found.\n")
        logMessage("File not found: " .. filePath)
        return
    end

    local content = file:read("*a")
    file:close()

    -- Send file content in chunks
    client:send(content)
    client:send("EOF") -- End of file marker
    logMessage("Sent file " .. filePath)
end

-- Main execution (Choose whether to run as client or server)
print("Run as client or server? (C/S):")
local choice = io.read():lower()
if choice == "c" then
    runClient()
else
    runServer()
end
