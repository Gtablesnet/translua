local socket = require("socket")
local lfs = require("lfs")
local md5 = require("md5") -- Assuming the md5 library is installed

-- Global variables
local logFile = "ftp_log.txt"
local logLevel = "INFO"  -- Set default log level to INFO (can be "DEBUG", "INFO", "ERROR")

-- Function to log messages with verbosity levels
function logMessage(message, level)
    -- Set default level to INFO if not provided
    level = level or "INFO"

    -- Check if the current log level allows this message to be logged
    if shouldLog(level) then
        local file = io.open(logFile, "a")
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. " [" .. level .. "] - " .. message .. "\n")
        file:close()
    end
end

-- Function to check if the current log level allows logging this message
function shouldLog(level)
    -- Define log level hierarchy (DEBUG < INFO < ERROR)
    local levels = { "DEBUG", "INFO", "ERROR" }
    local currentLevelIndex = table.indexOf(levels, logLevel)
    local messageLevelIndex = table.indexOf(levels, level)

    return messageLevelIndex >= currentLevelIndex
end

-- Helper function to find the index of a value in a table
function table.indexOf(tbl, value)
    for i, v in ipairs(tbl) do
        if v == value then
            return i
        end
    end
    return nil
end

-- Function to handle the client role
function runClient()
    print("Running as Client.")
    logMessage("Client started", "INFO")
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
    logMessage("Connected to server: " .. host .. ":" .. port, "INFO")

    -- Client communication loop
    while true do
        local command = getClientCommand()
        if command:lower() == "exit" then
            closeConnection(client)
            break
        end

        handleClientCommand(command, client)
    end

    -- Graceful cleanup
    cleanup(client)
end

-- Graceful cleanup function
function cleanup(client)
    print("Cleaning up resources...")
    logMessage("Cleaning up resources...", "INFO")
    if client then
        client:close()
        logMessage("Client connection closed.", "INFO")
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
        logMessage("Connection failed. Retrying... (" .. attempt .. "/" .. retries .. ")", "INFO")
        socket.sleep(2)  -- Wait before retrying
    end
    print("Failed to connect after " .. retries .. " attempts.")
    logMessage("Failed to connect after " .. retries .. " attempts.", "ERROR")
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
    logMessage("Connection error: " .. err, "ERROR")
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
        logMessage("Error sending command: " .. err, "ERROR")
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
        logMessage("Error receiving response: " .. err, "ERROR")
        return nil
    end
    return response
end

-- Function to validate the server's acknowledgment response
function validateServerAck(response)
    if response:match("File received successfully") then
        print("File transfer successful!")
        logMessage("File transfer successful", "INFO")
    elseif response:match("Error:") then
        print("Error occurred on server: " .. response)
        logMessage("Server error: " .. response, "ERROR")
    else
        print("Unexpected response from server: " .. response)
        logMessage("Unexpected server response: " .. response, "ERROR")
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
        logMessage("Error saving file: " .. err, "ERROR")
        return
    end

    local totalSize = 0
    local receivedData = ""
    -- Receive and write the file in chunks
    while true do
        local chunk, err = client:receive(1024)  -- Receive in 1KB chunks
        if err then
            print("Error receiving file chunk:", err)
            logMessage("Error receiving file chunk: " .. err, "ERROR")
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
    logMessage("File " .. filename .. " received, checksum: " .. checksum, "INFO")

    print("File saved as " .. filename)
    logMessage("File saved as " .. filename, "INFO")
end

-- Function to close the connection
function closeConnection(client)
    print("Closing connection...")
    logMessage("Closing connection", "INFO")
    client:close()
end

-- Function to handle the server role
function runServer()
    print("Running as Server.")
    logMessage("Server started", "INFO")
    local host, port = getServerDetailsForServer()

    -- Set up server and bind to specified host and port
    local server = assert(socket.bind(host, port))
    print("Server started on " .. host .. ":" .. port)
    logMessage("Server started on " .. host .. ":" .. port, "INFO")

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
            logMessage("Client disconnected or error: " .. err, "ERROR")
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
        client:send("Invalid command.\n")
        logMessage("Invalid command received: " .. data, "ERROR")
        return
    end

    -- Process the "get" command (file retrieval)
    if data:match("^get%s+(.+)$") then
        local filename = data:match("^get%s+(.+)$")
        sendFile(filename, client)
    elseif data:match("^exit$") then
        client:send("Goodbye!\n")
    else
        client:send("Unknown command.\n")
    end
end

-- Function to send a file to the client
function sendFile(filename, client)
    local file, err = io.open(filename, "rb")
    if not file then
        client:send("Error opening file: " .. err .. "\n")
        logMessage("Error opening file: " .. err, "ERROR")
        return
    end

    -- Read file contents and send to client
    local data = file:read("*a")
    client:send(data)
    file:close()
    print("File sent successfully!")
    logMessage("File sent successfully: " .. filename, "INFO")
end

-- Main execution
print("Select role: 1. Server 2. Client")
local role = tonumber(io.read())

if role == 1 then
    runServer()
elseif role == 2 then
    runClient()
else
    print("Invalid selection. Exiting.")
end
