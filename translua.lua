local socket = require("socket")
local lfs = require("lfs")
local md5 = require("md5") -- Assuming the md5 library is installed

-- Global variables
local logFile = "ftp_log.txt"
local logLevel = "INFO"  -- Set default log level to INFO (can be "DEBUG", "INFO", "ERROR")

-- Log level hierarchy
local levels = { DEBUG = 1, INFO = 2, ERROR = 3 }

-- Function to log messages with verbosity levels
function logMessage(message, level)
    level = level or "INFO"
    if levels[level] >= levels[logLevel] then
        local file = io.open(logFile, "a")
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. " [" .. level .. "] - " .. message .. "\n")
        file:close()
    end
end

-- Sanitize file paths to prevent directory traversal attacks
function sanitizeFilePath(path)
    return path:gsub("[%.%./\\]", "")  -- Remove parent directory references
end
-- Coroutine for receiving data
function receiveData(client)
    local data = ""
    while true do
        local chunk, err = client:receive(1024) -- Receive in 1KB chunks
        if err then
            if err == "timeout" then
                coroutine.yield() -- Yield control for non-blocking behavior
            else
                logMessage("Error receiving data: " .. err, "ERROR")
                break
            end
        elseif chunk == "EOF" then
            break -- End of file marker received
        else
            data = data .. chunk
            client:send("ACK") -- Acknowledge receipt
        end
    end
    return data
end

-- Coroutine for sending data
function sendData(client, data)
    local totalSent = 0
    local chunkSize = 1024
    while totalSent < #data do
        local chunk = data:sub(totalSent + 1, totalSent + chunkSize)
        local success, err = client:send(chunk)
        if not success then
            if err == "timeout" then
                coroutine.yield() -- Yield for non-blocking behavior
            else
                logMessage("Error sending data: " .. err, "ERROR")
                break
            end
        else
            totalSent = totalSent + #chunk
            local ack = client:receive()
            if ack ~= "ACK" then
                logMessage("Failed to receive acknowledgment for chunk", "ERROR")
                break
            end
        end
    end
    client:send("EOF")
end
-- Function to send a file using coroutines
function sendFileCoroutine(filename, client)
    local file, err = io.open(sanitizeFilePath(filename), "rb")
    if not file then
        client:send("Error opening file: " .. err .. "\n")
        logMessage("Error opening file: " .. err, "ERROR")
        return
    end

    local data = file:read("*a") -- Read entire file
    file:close()

    local sendCoroutine = coroutine.create(function()
        sendData(client, data)
    end)

    while coroutine.status(sendCoroutine) ~= "dead" do
        coroutine.resume(sendCoroutine)
    end
    logMessage("File sent successfully: " .. filename, "INFO")
end

-- Function to receive a file using coroutines
function receiveFileCoroutine(client, filename)
    local receiveCoroutine = coroutine.create(function()
        return receiveData(client)
    end)

    local receivedData = ""
    while coroutine.status(receiveCoroutine) ~= "dead" do
        local _, data = coroutine.resume(receiveCoroutine)
        if data then
            receivedData = receivedData .. data
        end
    end

    -- Save received data to a file
    local file, err = io.open(sanitizeFilePath(filename), "wb")
    if not file then
        logMessage("Error saving file: " .. err, "ERROR")
        return
    end
    file:write(receivedData)
    file:close()
    logMessage("File received and saved as " .. filename, "INFO")
end
-- Server communication handler
function handleServerCommunication(client)
    while true do
        local data, err = client:receive()
        if not data then
            logMessage("Client disconnected or error: " .. (err or "unknown"), "ERROR")
            break
        end

        if data:match("^get%s+(.+)$") then
            local filename = data:match("^get%s+(.+)$")
            sendFileCoroutine(filename, client)
        elseif data:match("^exit$") then
            client:send("Goodbye!\n")
            break
        else
            client:send("Unknown command.\n")
        end
    end
    client:close()
end

-- Function to run the server
function runServer()
    print("Enter IP address to bind (default: 127.0.0.1):")
    local host = io.read()
    if host == "" then host = "127.0.0.1" end
    print("Enter port to listen on (default: 69):")
    local port = tonumber(io.read())
    if not port then port = 69 end

    local server = assert(socket.bind(host, port))
    print("Server started on " .. host .. ":" .. port)
    logMessage("Server started on " .. host .. ":" .. port, "INFO")

    while true do
        print("Waiting for a client...")
        local client = server:accept()
        logMessage("Client connected", "INFO")
        handleServerCommunication(client)
    end
end
-- Function to run the client
function runClient()
    print("Enter server IP address:")
    local host = io.read()
    print("Enter server port:")
    local port = tonumber(io.read())

    local client = socket.tcp()
    client:settimeout(10)

    if not client:connect(host, port) then
        logMessage("Failed to connect to server", "ERROR")
        return
    end

    print("Connected to server.")
    logMessage("Connected to server: " .. host .. ":" .. port, "INFO")

    while true do
        print("Enter command (or 'exit' to quit):")
        local command = io.read()
        if command == "exit" then
            client:send(command)
            break
        elseif command:match("^get%s+(.+)$") then
            local filename = command:match("^get%s+(.+)$")
            client:send(command)
            receiveFileCoroutine(client, filename)
        else
            client:send(command)
            print("Server response: " .. (client:receive() or "No response"))
        end
    end
    client:close()
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
