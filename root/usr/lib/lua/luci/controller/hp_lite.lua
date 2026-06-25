module("luci.controller.hp_lite", package.seeall)

local SAVE_PATH = "/usr/bin/hp-lite"
local UPLOAD_TMP = "/tmp/hp-lite.upload"
local i18n_ok, i18n = pcall(require, "luci.i18n")

local function tr(key, fallback)
    local msgid = "hp-lite." .. key
    local text = i18n_ok and i18n and i18n.translate and i18n.translate(msgid) or msgid
    return text ~= msgid and text or fallback
end

local function is_hp_lite_installed(fs, sys)
    if fs.access(SAVE_PATH, "x") then
        return true
    end
    return sys.call("command -v hp-lite >/dev/null 2>&1") == 0
end

local function write_upload_json(http, ok, message)
    http.prepare_content("application/json")
    http.write_json({ ok = ok, message = message })
end

function index()
    local nixio = require "nixio"
    if not nixio.fs.access("/etc/config/hp-lite") then
        return
    end
    entry({"admin", "services", "hp-lite", "config"}, cbi("hp_lite/config"), "Client Configuration", 2).leaf = true
    entry({"admin", "services", "hp-lite"}, cbi("hp_lite/config"), "hp-lite Client", 60).dependent = true
    entry({"admin", "services", "hp-lite", "action"}, call("action_service")).leaf = true
    entry({"admin", "services", "hp-lite", "upload"}, call("upload_binary")).leaf = true
    entry({"admin","services","hp-lite","log"}, view("hp_lite/log"), "Runtime Log", 2)
    entry({"admin","services","hp-lite","get_log"}, call("get_log")).leaf = true
end

function action_service()
    local http = require "luci.http"
    local util = require "luci.util"

    local act = http.formvalue("act")
    local cmd = ""

    if act == "start" then
        cmd = "/etc/init.d/hp-lite start"
    elseif act == "stop" then
        cmd = "/etc/init.d/hp-lite stop"
    elseif act == "restart" then
        cmd = "/etc/init.d/hp-lite restart"
    end

    if #cmd > 0 then
        util.exec(cmd .. " >/dev/null 2>&1")
    end

    http.prepare_content("application/json")
    http.write_json({status = "ok", action = act})
end

function upload_binary()
    local http = require "luci.http"
    local sys = require "luci.sys"
    local fs = require "nixio.fs"

    local fp
    local upload_error
    os.remove(UPLOAD_TMP)

    http.setfilehandler(function(meta, chunk, eof)
        if meta and meta.name == "file" and meta.file and not fp and not upload_error then
            fp, upload_error = io.open(UPLOAD_TMP, "w")
        end

        if fp and chunk then
            fp:write(chunk)
        end

        if fp and eof then
            fp:close()
            fp = nil
        end
    end)

    http.formvalue("file")

    if fp then
        fp:close()
    end

    local stat = fs.stat(UPLOAD_TMP)
    if upload_error or not stat or stat.size == 0 then
        os.remove(UPLOAD_TMP)
        write_upload_json(http, false, tr("upload_failed", "Upload failed"))
        return
    end

    if is_hp_lite_installed(fs, sys) then
        sys.call("/etc/init.d/hp-lite stop >/dev/null 2>&1")
    end

    if sys.call("mv -f /tmp/hp-lite.upload /usr/bin/hp-lite >/dev/null 2>&1") ~= 0 then
        os.remove(UPLOAD_TMP)
        write_upload_json(http, false, tr("upload_failed", "Upload failed"))
        return
    end

    sys.call("chmod 755 /usr/bin/hp-lite >/dev/null 2>&1")
    if sys.call("[ -x /etc/init.d/hp-lite ]") == 0 then
        sys.call("/etc/init.d/hp-lite enable >/dev/null 2>&1")
    end
    sys.call("/etc/init.d/hp-lite restart >/dev/null 2>&1")

    write_upload_json(http, true, tr("uploaded_and_installed_successfully", "Uploaded and installed successfully"))
end

function get_log()
    local logfile = "/var/log/hp-lite/hp-lite.log"
    local max_lines = 300
    local content = ""
    local readable = false

    local f = io.open(logfile, "r")
    if f then
        local lines = {}
        for line in f:lines() do
            table.insert(lines, line)
            if #lines > max_lines then table.remove(lines,1) end
        end
        content = table.concat(lines, "\n")
        f:close()
        readable = true
    end

    local http = require "luci.http"
    http.prepare_content("application/json")
    http.write_json({log = content, readable = readable})
end
