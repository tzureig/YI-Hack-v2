var APP = APP || {};

APP.configurations = (function($) {

    function init() {
        registerEventHandler();
        fetchConfigs();
        fetchStatus();
    }

    function registerEventHandler() {
        $(document).on("click", '#button-save', function(e) {
            saveConfigs();
        });
    }

    function fetchConfigs() {
        loadingStatusElem = $('#loading-status');
        loadingStatusElem.text("Loading...");

        $.ajax({
            type: "GET",
            url: 'cgi-bin/get_configs.sh?conf=system',
            dataType: "json",
            success: function(response) {
                loadingStatusElem.fadeOut(500);

                // Generic: fill every element that has the matching data-key
                $.each(response, function(key, state) {
                    var el = $('[data-key="' + key + '"]');
                    if (el.length == 0)
                        return;
                    if (el.is('input[type="checkbox"]'))
                        el.prop('checked', state === 'yes');
                    else
                        el.prop('value', state);
                });
            },
            error: function(response) {
                console.log('error', response);
            }
        });
    }

    function saveConfigs() {
        var saveStatusElem;
        let configs = {};

        saveStatusElem = $('#save-status');

        saveStatusElem.text("Saving...");

        // Generic: send every element of the page that has a data-key
        $('#container [data-key]').each(function() {
            var key = $(this).attr('data-key');
            if ($(this).is('input[type="checkbox"]'))
                configs[key] = $(this).prop('checked') ? 'yes' : 'no';
            else
                configs[key] = $(this).prop('value');
        });

        if (configs["WD_PING_HOST"] && !/^[A-Za-z0-9.:_-]*$/.test(configs["WD_PING_HOST"])) {
            saveStatusElem.text("Failed");
            alert("Ping host not valid!");
            return;
        }
        if (configs["WD_NET_REBOOT_MIN"] !== undefined && !/^[0-9]+$/.test(configs["WD_NET_REBOOT_MIN"])) {
            saveStatusElem.text("Failed");
            alert("Reboot delay must be a number of minutes (0 = never)!");
            return;
        }

        var configData = JSON.stringify(configs);
        var escapedConfigData = configData.replace(/\\/g, "\\")
            .replace(/\\"/g, '\\"');

        $.ajax({
            type: "POST",
            url: 'cgi-bin/set_configs.sh?conf=system',
            data: escapedConfigData,
            dataType: "json",
            success: function(response) {
                saveStatusElem.text("Saved");
            },
            error: function(response) {
                saveStatusElem.text("Error while saving");
                console.log('error', response);
            }
        });
    }

    function fetchStatus() {
        $.ajax({
            type: "GET",
            url: 'cgi-bin/status.json',
            dataType: "json",
            success: function(response) {
                $.each(response, function(key, state) {
                    if (key == "go2rtc" && state == "no") {
                        $("#RTSP_ALT option[value='go2rtc']").remove();
                    }
                });
            },
            error: function(response) {
                console.log('error', response);
            }
        });
    }

    function validateHostname(hostname) {
        return /^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$/.test(hostname);
    }

    return {
        init: init
    };

})(jQuery);
