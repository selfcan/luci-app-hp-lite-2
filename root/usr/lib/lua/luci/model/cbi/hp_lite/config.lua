local uci = require "luci.model.uci".cursor()
local util = require "luci.util"
local sys = require "luci.sys"
local nixio = require "nixio"
local dispatcher = require "luci.dispatcher"

local FIXED_DOWNLOAD_PREFIX = "https://gitee.com/HServer/hp-lite/releases/download/latest/hp-lite-"
local INSTALL_DIR = "/usr/bin/"
local save_path = INSTALL_DIR .. "hp-lite"

local arch = sys.exec("uname -m"):gsub("%s+", "")
local arch_map = {
    ["i386"] = "386", ["i686"] = "386",
    ["x86_64"] = "amd64",
    ["aarch64"] = "arm64", ["armv8l"] = "arm64",
    ["armv7l"] = "armv7", ["armv6l"] = "armv7",
    ["mips"] = "mips", ["mipsel"] = "mipsle",
    ["mips64"] = "mips64", ["mips64el"] = "mips64le",
    ["ppc64le"] = "ppc64le",
    ["riscv64"] = "riscv64"
}
local download_arch = arch_map[arch] or arch

local function tr(key, fallback)
    local msgid = "hp-lite." .. key
    local text = translate(msgid)
    return text ~= msgid and text or fallback
end

-- ==== Map ====
local m = Map("hp-lite", translate(""))

-- ==================================================
-- General Settings
-- ==================================================
local s = m:section(NamedSection, "global", "hp-lite", tr("general_settings", "General Settings"))

local running = (sys.call("pgrep -f 'hp-lite' >/dev/null") == 0)
local status = s:option(DummyValue, "_status", tr("running_status", "Running Status"))
status.rawhtml = true
status.value = running
    and string.format("<b style='color:green'>%s</b>", tr("running", "Running"))
    or string.format("<b style='color:red'>%s</b>", tr("stopped", "Stopped"))

local connect = s:option(Value, "connect_code", tr("connection_code", "Connection Code"))
connect.placeholder = tr("connection_code_placeholder", "Connection code")

local retention = s:option(Value, "log_retention_days", tr("log_retention_days", "Log Retention Days"))
retention.default = "3"
retention.placeholder = "3"
retention.datatype = "range(1,3650)"
retention.rmempty = false

local start_btn = s:option(Button, "_start", tr("start_service", "Start Service"))
start_btn.inputstyle = "apply"
function start_btn.write()
    util.exec("/etc/init.d/hp-lite start >/dev/null 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/hp-lite"))
end

local stop_btn = s:option(Button, "_stop", tr("stop_service", "Stop Service"))
stop_btn.inputstyle = "reset"
function stop_btn.write()
    util.exec("/etc/init.d/hp-lite stop >/dev/null 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/hp-lite"))
end
local clear_btn = s:option(Button, "_clear", tr("clear_log", "Clear Log"))
clear_btn.inputstyle = "danger"
function clear_btn.write()
    nixio.fs.writefile("/var/log/hp-lite/hp-lite.log", "")
end

local up = m:section(TypedSection, "hp-lite", tr("install_upgrade", "Install hp-lite"))
up.anonymous = true


local function is_hp_lite_installed()
    if save_path and nixio.fs.access(save_path, "x") then
        return true
    end
    return sys.call("command -v hp-lite >/dev/null 2>&1") == 0
end

local info = up:option(DummyValue, "_arch", tr("system_architecture", "System Architecture"))
info.rawhtml = true
info.value = "<b>" .. download_arch .. "</b>"

local status = up:option(DummyValue, "_status", tr("install_status", "Install Status"))
status.rawhtml = true
if is_hp_lite_installed() then
    local version = sys.exec("hp-lite -v 2>/dev/null | head -n1")
    if version and version ~= "" then
        status.value = string.format(
            "<span style='color:green'>%s</span><br/><small>%s %s</small>",
            tr("installed", "Installed"),
            tr("version_label", "Version:"),
            version
        )
    else
        status.value = string.format("<span style='color:green'>%s</span>", tr("installed", "Installed"))
    end
else
    status.value = string.format("<span style='color:red'>%s</span>", tr("not_installed", "Not installed"))
end

local dl = up:option(Button, "_download", tr("remote_download", "Remote Download"))
dl.inputstyle = "apply"
function dl.write()
    local url = FIXED_DOWNLOAD_PREFIX .. download_arch
    if is_hp_lite_installed() then
        sys.exec("/etc/init.d/hp-lite stop >/dev/null 2>&1")
    end
    sys.exec(string.format(
        "wget -q -O %s %s || curl -sSL -o %s %s",
        save_path, url, save_path, url
    ))
    if nixio.fs.stat(save_path) then
        sys.exec("chmod 755 " .. save_path)
        if sys.call("[ -x /etc/init.d/hp-lite ]") == 0 then
            sys.exec("/etc/init.d/hp-lite enable >/dev/null 2>&1")
        end
        sys.exec("/etc/init.d/hp-lite restart >/dev/null 2>&1")
        m.message = tr("downloaded_and_installed_successfully", "Downloaded and installed successfully")
        luci.http.redirect(luci.dispatcher.build_url("admin/services/hp-lite"))
    else
        m.message = tr("download_failed", "Download failed")
    end
end

local remove_btn = up:option(Button, "_remove_installed", tr("remove_installed", "Remove Installed"))
remove_btn.inputstyle = "remove"
function remove_btn.write()
    sys.exec("/etc/init.d/hp-lite stop >/dev/null 2>&1")
    sys.exec("/etc/init.d/hp-lite disable >/dev/null 2>&1")
    sys.exec("rm -f /usr/bin/hp-lite /tmp/hp-lite.upload >/dev/null 2>&1")
    m.message = tr("removed_successfully", "Removed successfully")
    luci.http.redirect(luci.dispatcher.build_url("admin/services/hp-lite"))
end

local function html_escape(value)
    return tostring(value or "")
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
end

local upload_url = dispatcher.build_url("admin/services/hp-lite/upload")
local page_url = dispatcher.build_url("admin/services/hp-lite")
local token = dispatcher.context and dispatcher.context.authtoken or ""
if token ~= "" then
    upload_url = upload_url .. "?token=" .. token
end

local upload = up:option(DummyValue, "_local_upload", tr("local_upload", "Local Upload"))
upload.rawhtml = true
upload.value = string.format([[
<div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
    <input type="file" id="hp-lite-upload-file" style="display:none" />
    <button type="button" id="hp-lite-file-button" class="cbi-button">%s</button>
    <span id="hp-lite-file-name" style="min-width:120px">%s</span>
    <button type="button" id="hp-lite-upload-button" class="cbi-button cbi-button-apply">%s</button>
    <span id="hp-lite-upload-message" style="font-size:12px"></span>
</div>
<script type="text/javascript">
(function() {
    var file = document.getElementById("hp-lite-upload-file");
    var fileButton = document.getElementById("hp-lite-file-button");
    var fileName = document.getElementById("hp-lite-file-name");
    var button = document.getElementById("hp-lite-upload-button");
    var message = document.getElementById("hp-lite-upload-message");
    var uploadUrl = %q;
    var pageUrl = %q;
    var token = %q;
    var chooseText = %q;
    var uploadingText = %q;
    var requestFailedText = %q;
    var noFileChosenText = %q;

    function updateFileName() {
        if (!fileName) {
            return;
        }

        fileName.textContent = file && file.files && file.files.length
            ? file.files[0].name
            : noFileChosenText;
    }

    function show(text, color) {
        if (!message) {
            return;
        }
        message.textContent = text || "";
        message.style.color = color || "";
    }

    if (fileButton && file) {
        fileButton.onclick = function() {
            file.click();
        };
    }

    if (file) {
        file.onchange = updateFileName;
        updateFileName();
    }

    if (!button) {
        return;
    }

    button.onclick = function() {
        if (!file || !file.files || file.files.length === 0) {
            show(chooseText, "#b56b00");
            return;
        }

        if (typeof FormData === "undefined") {
            show(requestFailedText, "#c00");
            return;
        }

        var data = new FormData();
        data.append("token", token);
        data.append("file", file.files[0]);

        button.disabled = true;
        show(uploadingText, "");

        var xhr = new XMLHttpRequest();
        xhr.open("POST", uploadUrl, true);
        xhr.onreadystatechange = function() {
            var res = null;

            if (xhr.readyState !== 4) {
                return;
            }

            button.disabled = false;

            try {
                res = JSON.parse(xhr.responseText || "{}");
            } catch (e) {}

            if (xhr.status >= 200 && xhr.status < 300 && res && res.ok) {
                show(res.message || "", "green");
                window.setTimeout(function() {
                    window.location.href = pageUrl;
                }, 800);
            } else {
                show((res && res.message) || requestFailedText, "#c00");
            }
        };
        xhr.onerror = function() {
            button.disabled = false;
            show(requestFailedText, "#c00");
        };
        xhr.send(data);
    };
})();
</script>
]], html_escape(tr("choose_file", "Choose File")),
    html_escape(tr("no_file_chosen", "No file chosen")),
    html_escape(tr("local_upload", "Local Upload")),
    upload_url, page_url, token,
    tr("choose_file_first", "Please choose a file first."),
    tr("uploading", "Uploading..."),
    tr("upload_request_failed", "Upload request failed"),
    tr("no_file_chosen", "No file chosen"))

function m.on_after_apply(self, map)
    util.exec("uci commit hp-lite")
end
return m
