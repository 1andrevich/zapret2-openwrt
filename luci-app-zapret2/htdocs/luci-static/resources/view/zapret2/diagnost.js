'use strict';
'require baseclass';
'require fs';
'require poll';
'require uci';
'require ui';
'require view';
'require view.zapret2.tools as tools';

const btn_style_neutral  = 'btn';
const btn_style_action   = 'btn cbi-button-action';
const btn_style_positive = 'btn cbi-button-save important';
const btn_style_negative = 'btn cbi-button-reset important';
const btn_style_warning  = 'btn cbi-button-negative';
const btn_style_success  = 'btn cbi-button-success important';

const fn_dwc_sh     = '/opt/'+tools.appName+'/dwc.sh';
const fn_test_sh    = '/opt/'+tools.appName+'/strategy_test.sh';
const fn_webrtc_sh  = '/opt/'+tools.appName+'/discord_webrtc_test.sh';

return baseclass.extend({
    appendLog: function(msg, end = '\n')
    {
        this.logArea.value += msg + end;
        this.logArea.scrollTop = this.logArea.scrollHeight;
    },

    setBtnMode: function(check1, check2, check3, check4, cancel)
    {
        if (this.btn_stratcheck)  this.btn_stratcheck.disabled  = check1 ? false : true;
        if (this.btn_sitescheck)  this.btn_sitescheck.disabled  = check2 ? false : true;
        if (this.btn_dpicheck)    this.btn_dpicheck.disabled    = check3 ? false : true;
        if (this.btn_webrtc)      this.btn_webrtc.disabled      = check4 ? false : true;
        if (this.btn_cancel)      this.btn_cancel.disabled      = cancel ? false : true;
    },

    strategyCheck: async function()
    {
        this._action = 'strategyCheck';
        this.setBtnMode(0, 0, 0, 0, 0);
        this.appendLog('Запуск тестирования стратегии и сервисов...');
        let cmd = [ fn_test_sh ];
        return tools.execAndRead({
            cmd: cmd,
            log: '/tmp/'+tools.appName+'_strategy_test.log',
            logArea: this.logArea,
            callback: this.execAndReadCallback,
            ctx: this,
        });
    },

    webrtcCheck: async function()
    {
        this._action = 'webrtcCheck';
        this.setBtnMode(0, 0, 0, 0, 0);
        this.appendLog('Запуск проверки Discord Voice и WebRTC (UDP)...');
        let cmd = [ fn_webrtc_sh ];
        return tools.execAndRead({
            cmd: cmd,
            log: '/tmp/'+tools.appName+'_webrtc_test.log',
            logArea: this.logArea,
            callback: this.execAndReadCallback,
            ctx: this,
        });
    },

    dpiCheck: async function()
    {
        this._action = 'dpiCheck';
        this.setBtnMode(0, 0, 0, 0, 0);
        this.appendLog('DPI check [tcp 16-20]...');
        this.appendLog('Original sources: https://github.com/hyperion-cs/dpi-checkers');
        this.appendLog('WEB-version: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/');
        let cmd = [ fn_dwc_sh ];
        let resolve_dns = document.getElementById('cfg_resolve_dns');
        let dns_ip = resolve_dns ? resolve_dns.options[resolve_dns.selectedIndex].text : null;
        if (dns_ip && dns_ip != 'default') {
            cmd.push(...[ '-d', dns_ip.trim() ]);
        }
        return tools.execAndRead({
            cmd: cmd,
            log: '/tmp/'+tools.appName+'_dwc.log',
            logArea: this.logArea,
            callback: this.execAndReadCallback,
            ctx: this,
        });
    },

    sitesCheck: async function()
    {
        this._action = 'sitesCheck';
        this.setBtnMode(0, 0, 0, 0, 0);
        this.appendLog('Sites check...');
        let cmd = [ fn_dwc_sh ];
        let resolve_dns = document.getElementById('cfg_resolve_dns');
        let dns_ip = resolve_dns ? resolve_dns.options[resolve_dns.selectedIndex].text : null;
        if (dns_ip && dns_ip != 'default') {
            cmd.push(...[ '-d', dns_ip.trim() ]);
        }
        cmd.push('-s');  // mode: check sites
        return tools.execAndRead({
            cmd: cmd,
            log: '/tmp/'+tools.appName+'_dwc.log',
            logArea: this.logArea,
            callback: this.execAndReadCallback,
            ctx: this,
        });
    },

    execAndReadCallback: function(rc, txt = '')
    {
        this.setBtnMode(1, 1, 1, 1, 1);
        if (rc == 0 && txt) {
            this.appendLog('=========================================================');
            return;
        }
        if (rc >= 500) {
            if (txt) {
                this.appendLog(txt.startsWith('ERROR') ? txt : 'ERROR: ' + txt);
            } else {
                this.appendLog('ERROR: ' + this._action + ': Terminated with error code = ' + rc);
            }
        } else {
            this.appendLog('ERROR: Process finished with retcode = ' + rc);
        }
        this.appendLog('=========================================================');
    },

    openDiagnostDialog: function(pkg_arch, auto_run_test = false)
    {
        this.pkg_arch = pkg_arch;

        let DNS_LIST = [
            '8.8.8.8',          // Google
            '8.8.4.4',          // Google
            '1.1.1.1',          // Cloudflare
            '1.0.0.1',          // Cloudflare
            '9.9.9.9',          // Quad9
            '149.112.112.112',  // Quad9
            '208.67.222.222',   // OpenDNS
            '208.67.220.220',   // OpenDNS
            '8.26.56.26',       // Comodo
            '8.20.247.20',      // Comodo
            '64.6.64.6',        // Verisign
            '64.6.65.6',        // Verisign
        ];
        let dns_list = [ ];
        dns_list.push( E('option', { value: 'dns_default' }, [ 'default' ] ) );
        for (let id = 0; id < DNS_LIST.length; id++) {
            let dns_ipaddr = '' + DNS_LIST[id];
            let val = 'dns_' + dns_ipaddr.replace(/\./g, '_');
            dns_list.push( E('option', { value: val }, [ dns_ipaddr ] ));
        } 
        let resolve_dns = E('label', [
            _('Resolve IP-Addr via') + ': ',
            E('select', { id: 'cfg_resolve_dns' }, dns_list)
        ]);
 
        this.logArea = E('textarea', {
            'id': 'widget.modal_content',
            'readonly': true,
            'style': 'width:100% !important; font-family: monospace;',
            'rows': 26,
            'wrap': 'off',
        });

        this.btn_cancel = E('button', {
            'id': 'btn_cancel',
            'name': 'btn_cancel',
            'class': btn_style_warning,
        }, _('Cancel'));
        this.btn_cancel.onclick = ui.hideModal;

        this.btn_stratcheck = E('button', {
            'id': 'btn_stratcheck',
            'name': 'btn_stratcheck',
            'class': btn_style_action,
        }, _('Тест стратегии'));
        this.btn_stratcheck.onclick = ui.createHandlerFn(this, this.strategyCheck);

        this.btn_dpicheck = E('button', {
            'id': 'btn_dpicheck',
            'name': 'btn_dpicheck',
            'class': btn_style_action,
        }, _('DPI check'));
        this.btn_dpicheck.onclick = ui.createHandlerFn(this, this.dpiCheck);

        this.btn_sitescheck = E('button', {
            'id': 'btn_sitescheck',
            'name': 'btn_sitescheck',
            'class': btn_style_action,
        }, _('Sites check'));
        this.btn_sitescheck.onclick = ui.createHandlerFn(this, this.sitesCheck);

        this.btn_webrtc = E('button', {
            'id': 'btn_webrtc',
            'name': 'btn_webrtc',
            'class': btn_style_action,
        }, _('Discord Voice'));
        this.btn_webrtc.onclick = ui.createHandlerFn(this, this.webrtcCheck);
        
        ui.showModal(_('Диагностика и тестирование стратегии'), [
            E('div', { 'class': 'cbi-section' }, [
                resolve_dns,
                E('br'), E('br'),
                this.logArea,
            ]),
            E('div', { 'style': 'display:flex; justify-content:space-between; align-items:center; margin-top:1px;' }, [
                E('div', { 'class': 'left' }, [
                    this.btn_stratcheck,
                    ' ',
                    this.btn_sitescheck,
                    ' ',
                    this.btn_dpicheck,
                    ' ',
                    this.btn_webrtc,
                ]),
                E('div', { 'class': 'right' }, [
                    ' ',
                    this.btn_cancel,
                ]),
            ]),
        ]);

        if (auto_run_test) {
            window.setTimeout(() => { this.strategyCheck(); }, 300);
        }
    }    
});
