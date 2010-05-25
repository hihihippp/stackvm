// Connect to VMs over rfb

var sys = require('sys');
var fs = require('fs');
var base64_encode = require('base64').encode;
var spawn = require('child_process').spawn;

var Buffer = require('buffer').Buffer;
var Png = require('png').Png;
var RFB = require('rfb').RFB;

var EventEmitter = require('events').EventEmitter;

VM.prototype = new EventEmitter;
exports.VM = VM;
function VM (opts) {
    var vm = this;
    var clients = {};
    var qemu;
    var rfb;
    
    this.status = 'stopped';
    
    this.start = function () {
        /* run a qemu on our own for now (otherwise it gets booted
        ** and shut down all the time)
        qemu = spawn(
            'qemu',
            [ '-vnc', '0:' + (opts.port - 5900), opts.image ]
        );
        
        qemu.addListener('exit', function (code, signal) {
            this.status = 'stopped';
            rfb.removeListener('raw', raw);
        });
        */

        this.status = 'running';
        
        rfb = new RFB(opts || {});
        rfb.addListener('raw', function (raw) {
            var png = new Png(raw.fb, raw.width, raw.height).encode();
            var pngBuf = new Buffer(png.length);
            pngBuf.write(png, 'binary');

            vm.emit('png', {
                vm_id : opts.id,
                action : 'update_screen',
                png64 : base64_encode(pngBuf),
                width : raw.width,
                height : raw.height,
                x : raw.x,
                y : raw.y
            });
        });
        rfb.addListener('copyRect', function (rect) {
            vm.emit('copyRect', {
                vm_id : opts.id,
                action : 'copy_rect',
                width : rect.width,
                height : rect.height,
                dstX : rect.dstX,
                dstY : rect.dstY,
                srcX : rect.srcX,
                srcY : rect.srcY
            });
        });
    };
    
    this.stop = function () {
        if (qemu) qemu.kill('SIGHUP');
    };
    
    this.restart = function () {
        qemu.stop();
        qemu.start();
    };
    
    this.attach = function (client) {
        clients[client] = {};
        clients[client]['send'] = function (msg) {
            client.send(JSON.stringify(msg));
        };
        this.addListener('png', clients[client]['send']);
        this.addListener('copyRect', clients[client]['send']);
    };
    
    this.detach = function (client) {
        this.removeListener('png', clients[client]['send']);
        this.removeListener('copyRect', clients[client]['send']);
        delete clients[client];
    };

    this.keyDown = function (client, key) {
        rfb.sendKeyDown(key);
    };

    this.keyUp = function (client, key) {
        rfb.sendKeyUp(key);
    };
}
