var APP = APP || {};

/*
 * Smart Home page (Home Assistant, Frigate, Scrypted, UniFi Protect): shows ready-to-copy configuration with the real
 * addresses of this camera. Passwords never leave the camera, so the
 * snippets contain the placeholder PASSWORD.
 *
 * ES5 on purpose (the build uses yui-compressor).
 */
APP.homeassistant = (function($) {

    var previewTimer = null;
    var info = {
        ip: window.location.hostname,
        httpPort: window.location.port || '80',
        rtspPort: '554',
        user: '',
        hasPassword: false,
        name: 'kamera',
        streams: 'both',
        rtsp: 'yes',
        onvif: 'yes',
        mqtt: 'no',
        mqttPrefix: 'yicam',
        mqttHost: ''
    };

    function init() {
        loadConfig();
        startPreview();
        $(document).on('click', '.tz-copy', function() {
            var pre = $(this).closest('pre');
            var text = pre.clone().children('.tz-copy').remove().end().text();
            copyText(text, $(this));
        });
        window.addEventListener('pagehide', stopPreview);
    }

    function slug(s) {
        s = String(s || 'kamera').toLowerCase()
            .replace(/ä/g, 'ae').replace(/ö/g, 'oe').replace(/ü/g, 'ue').replace(/ß/g, 'ss')
            .replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
        return s || 'kamera';
    }

    function badge(el, cls, text) {
        $(el).html('').append($('<span>').addClass('tz-badge ' + cls).text(text));
    }

    function loadConfig() {
        $.ajax({
            type: 'GET',
            url: 'cgi-bin/get_configs.sh?conf=system',
            dataType: 'json',
            success: function(c) {
                if (c.RTSP_PORT && /^[0-9]+$/.test(c.RTSP_PORT)) info.rtspPort = c.RTSP_PORT;
                info.user = c.USERNAME || '';
                info.hasPassword = (c.PASSWORD === '********');
                info.streams = c.RTSP_STREAM || 'both';
                info.rtsp = c.RTSP || 'yes';
                info.onvif = c.ONVIF || 'yes';
                info.mqtt = c.MQTT || 'no';
                if (c.HOSTNAME) info.name = c.HOSTNAME;
                if (typeof hostname !== 'undefined' && hostname) info.name = hostname;
                loadMqtt();
            },
            error: function() {
                render();
            }
        });
        loadHealth();
    }

    function loadMqtt() {
        $.ajax({
            type: 'GET',
            url: 'cgi-bin/get_configs.sh?conf=mqtt',
            dataType: 'json',
            success: function(c) {
                if (c.MQTT_PREFIX) info.mqttPrefix = c.MQTT_PREFIX;
                if (c.MQTT_IP && c.MQTT_IP !== '0.0.0.0') info.mqttHost = c.MQTT_IP;
                render();
            },
            error: function() {
                render();
            }
        });
    }

    function loadHealth() {
        $.ajax({
            type: 'GET',
            url: 'cgi-bin/health.sh',
            dataType: 'json',
            success: function(h) {
                if (h.status === 'ok') {
                    badge('#ha-health', 'ok', 'Online');
                } else {
                    badge('#ha-health', 'warn', 'Degraded (rmm: ' + h.rmm + ', rtsp: ' + h.rtsp + ')');
                }
            },
            error: function(xhr) {
                var h = xhr && xhr.responseJSON;
                badge('#ha-health', 'warn', h ? 'Degraded (rmm: ' + h.rmm + ', rtsp: ' + h.rtsp + ')' : 'Unknown');
            }
        });
    }

    function rtspUrl(path, withAuth) {
        var auth = '';
        if (withAuth && info.user) {
            auth = info.user + ':PASSWORD@';
        }
        var port = (info.rtspPort === '554') ? '' : ':' + info.rtspPort;
        return 'rtsp://' + auth + info.ip + port + '/' + path;
    }

    function httpBase() {
        return 'http://' + info.ip + (info.httpPort === '80' ? '' : ':' + info.httpPort);
    }

    function setCode(id, text) {
        var pre = $('#' + id);
        pre.text(text);
        pre.prepend($('<input>', { type: 'button', value: 'Copy', 'class': 'tz-copy' }));
    }

    function render() {
        var n = slug(info.name);
        var main = rtspUrl('ch0_0.h264', true);
        var sub = rtspUrl('ch0_1.h264', true);

        // Status badges
        if (info.rtsp !== 'yes') {
            badge('#ha-streams', 'bad', 'RTSP off');
        } else if (info.streams === 'both') {
            badge('#ha-streams', 'ok', 'Main + substream');
        } else {
            badge('#ha-streams', 'warn', 'Only ' + info.streams + ' – set "both" in Configurations');
        }
        badge('#ha-onvif', info.onvif === 'yes' ? 'ok' : 'warn', info.onvif === 'yes' ? 'On' : 'Off');
        badge('#ha-mqtt', info.mqtt === 'yes' ? 'ok' : 'warn',
              info.mqtt === 'yes' ? 'On' + (info.mqttHost ? ' (' + info.mqttHost + ')' : '') : 'Off');
        if (info.user && info.hasPassword) {
            badge('#ha-auth', 'ok', 'User ' + info.user);
        } else {
            badge('#ha-auth', 'bad', 'No password – set one under Configurations');
        }

        setCode('ha-onvif-code',
            'Host:      ' + info.ip + '\n' +
            'Port:      ' + info.httpPort + '\n' +
            'Username:  ' + (info.user || 'USER') + '\n' +
            'Password:  PASSWORD');

        setCode('ha-go2rtc-code',
            'go2rtc:\n' +
            '  streams:\n' +
            '    ' + n + ':\n' +
            '      - ' + main + '\n' +
            '    ' + n + '_sub:\n' +
            '      - ' + sub);

        var p = info.mqttPrefix;
        setCode('ha-mqtt-code',
            '# Topics of this camera (prefix ' + p + ')\n' +
            '# ' + p + '/status            online | offline\n' +
            '# ' + p + '/motion_detection  motion_start | motion_stop | human | vehicle | animal\n' +
            '# ' + p + '/motion_files      path of the new recording\n' +
            '#\n' +
            '# Example automation: notify when a person is detected\n' +
            'automation:\n' +
            '  - alias: "' + info.name + ': person detected"\n' +
            '    trigger:\n' +
            '      - platform: mqtt\n' +
            '        topic: "' + p + '/motion_detection"\n' +
            '        payload: "human"\n' +
            '    action:\n' +
            '      - service: notify.notify\n' +
            '        data:\n' +
            '          message: "Person at ' + info.name + '"');

        setCode('ha-health-code',
            'binary_sensor:\n' +
            '  - platform: rest\n' +
            '    name: ' + n + '_online\n' +
            '    resource: ' + httpBase() + '/cgi-bin/health.sh\n' +
            '    username: ' + (info.user || 'USER') + '\n' +
            '    password: PASSWORD\n' +
            '    authentication: basic\n' +
            '    device_class: connectivity\n' +
            '    scan_interval: 60\n' +
            '    value_template: "{{ value_json.status == \'ok\' }}"');

        setCode('ha-frigate-code',
            'cameras:\n' +
            '  ' + n + ':\n' +
            '    ffmpeg:\n' +
            '      inputs:\n' +
            '        - path: ' + sub + '\n' +
            '          roles: [detect]\n' +
            '        - path: ' + main + '\n' +
            '          roles: [record]\n' +
            '    detect:\n' +
            '      width: 640\n' +
            '      height: 360\n' +
            '      fps: 5');

        setCode('ha-scrypted-code',
            'ONVIF Camera Plugin\n' +
            '  IP Address:  ' + info.ip + '\n' +
            '  HTTP Port:   ' + info.httpPort + '\n' +
            '  Username:    ' + (info.user || 'USER') + '\n' +
            '  Password:    PASSWORD\n' +
            '\n' +
            'RTSP Camera Plugin (alternative)\n' +
            '  Main stream: ' + rtspUrl('ch0_0.h264', false) + '\n' +
            '  Substream:   ' + rtspUrl('ch0_1.h264', false) + '\n' +
            '  Snapshot:    ' + httpBase() + '/cgi-bin/snapshot.sh?res=high\n' +
            '  Username:    ' + (info.user || 'USER') + '\n' +
            '  Password:    PASSWORD');

        setCode('ha-unifi-code',
            'Address:   ' + info.ip + '\n' +
            'Port:      ' + info.httpPort + '\n' +
            'ONVIF URL: ' + httpBase() + '/onvif/device_service\n' +
            'Username:  ' + (info.user || 'USER') + '\n' +
            'Password:  PASSWORD');

        setCode('ha-card-code',
            'type: picture-glance\n' +
            'title: ' + info.name + '\n' +
            'camera_image: camera.' + n + '\n' +
            'camera_view: live\n' +
            'entities: []');
    }

    function startPreview() {
        var img = document.getElementById('ha-preview');
        function next() {
            var probe = new Image();
            probe.onload = function() {
                img.src = probe.src;
                schedule();
            };
            probe.onerror = function() {
                $('#ha-preview-text').text('Snapshot not available.');
                schedule();
            };
            probe.src = 'cgi-bin/snapshot.sh?res=low&watermark=yes&nocache=' + Date.now();
        }
        function schedule() {
            previewTimer = setTimeout(next, 5000);
        }
        next();
    }

    function stopPreview() {
        if (previewTimer) {
            clearTimeout(previewTimer);
            previewTimer = null;
        }
    }

    function copyText(text, button) {
        function done() {
            var old = button.val();
            button.val('Copied');
            setTimeout(function() { button.val(old); }, 1500);
        }
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text).then(done, function() { fallback(); });
        } else {
            fallback();
        }
        function fallback() {
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.style.position = 'fixed';
            ta.style.opacity = '0';
            document.body.appendChild(ta);
            ta.select();
            try { document.execCommand('copy'); done(); } catch (e) {}
            document.body.removeChild(ta);
        }
    }

    return {
        init: init
    };

})(jQuery);
