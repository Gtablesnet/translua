local socket = require("socket")

-- Function to handle the client role
function runClient()
    print("Running as Client.")
    local client = socket.tcp()

    -- Get server details
    print("Enter the server IP Address:")
    local host = io.read()
    print("Enter the server port:")
    local port = tonumber(io.read())

    -- Connect to the server
    local success, err = client:connect(host, port)
    if not success then
        print("Failed to connect to server:", err)
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

        client:send(command .. "\n") -- Send command to server
        local response, receive_err = client:receive("*a") -- Wait for response
        if response then
            print("Server response:\n" .. response)
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

    local server = assert(socket.bind(host, port))
    print("Server started on " .. host .. ":" .. port)

    while true do
        print("Waiting for a client to connect...")
        local client = server:accept() -- Accept a client connection
        print("Client connected!")

        -- Communication loop
        while true do
            local data, err = client:receive() -- Receive data
            if not data then
                print("Client disconnected or error:", err)
                break
            end

            print("Received:", data)
            -- Call commandHandling with data and client
            commandHandling(data, client)
        end
        client:close()
        print("Client connection closed.")
    end
end

-- Function to handle client commands
function commandHandling(data, client)
    -- Command handling
    if data:match("^dir$") then
        local handle = io.popen("dir")
        local result = handle:read("*a")
        handle:close()
        client:send(result)
    elseif data:match("^cd%s+(.+)$") then
        local dir = data:match("^cd%s+(.+)$")
        local success, msg = lfs.chdir(dir)
        if success then
            client:send("Changed directory to " .. dir .. "\n")
        else
            client:send("Failed to change directory: " .. msg .. "\n")
        end
    elseif data:match("^save%s+(.+)$") then
        local content = data:match("^save%s+(.+)$")
        if content then
            saveDataToFile(content)
            client:send("Data saved.\n")
        else
            client:send("Invalid save command.\n")
        end
    elseif data:match("^get%s+(.+)$") then
        local filePath = data:match("^get%s+(.+)$")
        if filePath then
            local fileData = getFile(filePath)
            if fileData then
                client:send(fileData .. "\n")
            else
                client:send("Error reading file.\n")
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
        return
    end
    file:write(data)
    file:close()
    print("Data saved to file:", filename)
end

-- Function to read file content
function getFile(filePath)
    local file, err = io.open(filePath, "r")
    if not file then
        print("Failed to open file:", err)
        return nil
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
