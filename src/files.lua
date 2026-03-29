-- @version 1.0.1
-- @location /libs/
-- @description File system utility library for reading, writing, and managing files
-- @warning Malicious actions can be taken with this library, use with caution!!

---@class FileData
---@field name string File name
---@field absolutePath string Full path to file
---@field parent string Parent directory path
---@field exists boolean Whether file exists
---@field isFile boolean Whether path is a file
---@field isDirectory boolean Whether path is a directory
---@field isHidden boolean Whether file is hidden
---@field lastModified number Last modified timestamp (divide by 1000 for epoch)
---@field size number File size in bytes
---@field permissions table File permission flags

---@class Files
---@field getFiles function(directory: string): table Get list of files in a directory
---@field getFileData function(filePath: string): FileData|nil Get detailed file information
---@field getDirectories function(directory: string): table Get list of subdirectories
---@field getInstanceDir function(): string Get Minecraft instance directory
---@field readFile function(file: string): string|nil Read text file contents
---@field writeFile function(file: string, text: string): boolean Write text to file
---@field writeBinaryFile function(file: string, data: string|table): boolean Write binary data to file
---@field deleteFile function(filePath: string): boolean Delete a file
---@field deleteDirectory function(filePath: string): boolean Delete an empty directory
---@field deleteDirectoryRecursive function(directoryPath: string): boolean Recursively delete directory and contents

---@type Files
local File = luajava.bindClass("java.io.File")
local Files = luajava.bindClass("java.nio.file.Files")
local Array = luajava.bindClass("java.lang.reflect.Array")
local StandardCharsets = luajava.bindClass("java.nio.charset.StandardCharsets")
local Paths = luajava.bindClass("java.nio.file.Paths")
local System = luajava.bindClass("java.lang.System")
local files = {}

---Get list of file names in a directory
---@param directory string Path to the directory
---@return table Array of file names
function files.getFiles(directory)
 	local filesList = {}
 	local dir = luajava.newInstance("java.io.File", directory)

 	if dir:exists() and dir:isDirectory() then
 		local filesArray = dir:listFiles()
 		
 		if filesArray ~= nil then
 			local length = Array:getLength(filesArray)
 			for i = 0, length - 1 do
 				local file = Array:get(filesArray, i)
 				table.insert(filesList, file:getName())
 			end
 		end
 	end
 	return filesList
end

---Get detailed information about a file
---@param filePath string Path to the file
---@return FileData|nil Table containing file data, or nil if file doesn't exist
function files.getFileData(filePath)
    local file = luajava.newInstance("java.io.File", filePath)
    if not file:exists() then return nil end

    local data = {}

    data.name = file:getName()
    data.absolutePath = file:getAbsolutePath()
    data.parent = file:getParent()
    data.exists = file:exists()
    data.isFile = file:isFile()
    data.isDirectory = file:isDirectory()
    data.isHidden = file:isHidden()
    data.lastModified = file:lastModified() -- returns long timestamp (divide by 1000 to get epoch time)
    data.size = file:length() -- in bytes

    -- Permissions
    data.permissions = {
        canRead = file:canRead(),
        canWrite = file:canWrite(),
        canExecute = file:canExecute()
    }
    return data
end

---Get list of subdirectories in a directory
---@param directory string Path to the directory
---@return table Array of directory names
function files.getDirectories(directory)
    local dirList = {}
    local dir = luajava.newInstance("java.io.File", directory)
    if dir:exists() and dir:isDirectory() then
        local filesArray = dir:listFiles()
        if filesArray ~= nil then
            local length = Array:getLength(filesArray)
            for i = 0, length - 1 do
                local file = Array:get(filesArray, i)
                if file:isDirectory() then
                    table.insert(dirList, file:getName())
                end
            end
        end
    end
    return dirList
end

---Get the Minecraft instance working directory
---@return string The current working directory path
function files.getInstanceDir()
    return System:getProperty("user.dir")
end

---Read the entire contents of a text file
---@param file string Path to the file
---@return string|nil File contents as string, or nil on error
function files.readFile(file)
    local f = io.open(file, "r")
    if not f then
        print("Error opening file: " .. (err or "unknown"))
        return nil
    end
    local content = f:read("*a")
    f:close()
    return content
end

---Write plain text to a file using "w" mode
---@param file string Path to the file
---@param text string Text content to write
---@return boolean True if successful, false otherwise
function files.writeFile(file, text)
    local f, err = io.open(file, "w")
    if not f then
        print("Error opening file for writing: " .. (err or "unknown"))
        return false
    end
    f:write(text)
    f:close()
    return true
end

---Write binary data to a file using "wb" mode
---@param file string Path to the file
---@param data string|table Binary data to write (string or byte array table)
---@return boolean True if successful, false otherwise
function files.writeBinaryFile(file, data)
    local f, err = io.open(file, "wb")
    if not f then
        print("Error opening file for binary writing: " .. (err or "unknown"))
        return false
    end

    if type(data) == "table" then
        -- Handle byte array (table of numbers)
        local parts = {}
        for i = 1, #data do
            local b = data[i]
            -- Convert signed byte (-128 to 127) to unsigned (0-255) if necessary
            if type(b) == "number" then
                if b < 0 then b = b + 256 end
                table.insert(parts, string.char(b))
            end
            
            -- Write in chunks of 4096 bytes to be memory efficient
            if i % 4096 == 0 then
                f:write(table.concat(parts))
                parts = {}
            end
        end
        f:write(table.concat(parts))
    else
        -- Handle string data
        f:write(data)
    end

    f:close()
    return true
end

---Delete a file
---@param filePath string Path to the file
---@return boolean True if deleted, false otherwise
function files.deleteFile(filePath)
    local file = luajava.newInstance("java.io.File", filePath)
    if file:exists() and file:isFile() then
        return file:delete()
    else
        print("File does not exist or is not a file: " .. filePath)
        return false
    end
end

---Delete an empty directory
---@param filePath string Path to the directory
---@return boolean True if deleted, false otherwise
function files.deleteDirectory(filePath)
    local file = luajava.newInstance("java.io.File", filePath)
    if file:exists() and file:isDirectory() then
        return file:delete()
    else
        print("Directory does not exist or is not a directory: " .. filePath)
        return false
    end
end

---Recursively delete a directory and all its contents
---@param directoryPath string Path to the directory
---@return boolean True if deleted, false otherwise
function files.deleteDirectoryRecursive(directoryPath)
    local dir = luajava.newInstance("java.io.File", directoryPath)
    if not dir:exists() then
        print("Directory does not exist: " .. directoryPath)
        return false
    end

    local function deleteRecursively(fileObj)
        if fileObj:isDirectory() then
            local filesArray = fileObj:listFiles()
            if filesArray ~= nil then
                local length = Array:getLength(filesArray)
                for i = 0, length - 1 do
                    local childFile = Array:get(filesArray, i)
                    if not deleteRecursively(childFile) then
                        return false
                    end
                end
            end
        end
        return fileObj:delete()
    end

    return deleteRecursively(dir)
end

return files