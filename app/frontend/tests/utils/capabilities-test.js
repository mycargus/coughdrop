import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { db_wait } from 'frontend/tests/helpers/ember_helper';
import capabilities from '../../utils/capabilities';
import Ember from 'ember';

describe("capabilities", function() {
  describe("volume_check", function() {
    it("should return a rejecting promise by default", function() {
      stub(window, 'plugin', null);
      var done = false;
      capabilities.volume_check().then(null, function() {
        done = true;
      });
      waitsFor(function() { return done; });
      runs();
    });

    it("should return the value passed by the plugin", function() {
      var attempts = 0;
      stub(window, 'plugin', {
        volume: {
          getVolume: function(callback) {
            attempts++;
            if(attempts == 1) {
              callback(100);
            } else {
              callback(0.5);
            }
          }
        }
      });
      var result = null;
      capabilities.volume_check().then(function(res) {
        result = res;
      });
      waitsFor(function() { return result == 100; });
      runs(function() {
        capabilities.volume_check().then(function(res) {
          result = res;
        });
      });
      waitsFor(function() { return result == 0.5; });
      runs();
    });
  });

  describe('silent_mode', function() {
    it('should return a promise', function() {
      var res = capabilities.silent_mode();
      expect(res.then).toNotEqual(undefined);
    });

    it('should resolve false if plugin not found', function() {
      stub(window, 'cordova', {});
      var done = false;
      capabilities.silent_mode().then(function(res) {
        done = true;
        expect(res).toEqual(false);
      });
      waitsFor(function() { return done; });
      runs();
    });

    it('should resolve true if muted', function() {
      stub(window, 'cordova', {plugins: {SilentMode: {
        isMuted: function(yes, no) {
          yes();
        }
      }}});
      var done = false;
      capabilities.silent_mode().then(function(res) {
        done = true;
        expect(res).toEqual(true);
      });
      waitsFor(function() { return done; });
      runs();
    });

    it('should resolve false if not muted', function() {
      stub(window, 'cordova', {plugins: {SilentMode: {
        isMuted: function(yes, no) {
          no();
        }
      }}});
      var done = false;
      capabilities.silent_mode().then(function(res) {
        done = true;
        expect(res).toEqual(false);
      });
      waitsFor(function() { return done; });
      runs();
    });
  });

  describe("setup_database", function() {

    it("should try flushing databases on error", function() {
      db_wait(function() {
        var db_req = { };
        var attempt = 0;
        var deleted_databases = [];
        var other = "coughDropStorage::bacon===abcdefg";
        var db_key = null;
        stub(capabilities, 'db', undefined);
        stub(capabilities.idb, 'open', function(key, revision) {
          db_key = key;
          attempt++;
          var evt = {
            attempt: attempt
          };
          Ember.run.later(function() {
            db_req.onerror(evt);
            if(attempt == 2) {
              expect(deleted_databases).toEqual([key]);
            } else if(attempt == 4) {
              expect(deleted_databases).toEqual([key, other]);
            }
          }, 10);
          return db_req;
        });
        waitsFor(function() { return attempt >= 4; });
        runs(function() {
          expect(deleted_databases).toEqual([db_key, other]);
          expect(capabilities.dbman.db_error_event.attempt >= 3).toEqual(true);
        });
        stub(capabilities.idb, 'webkitGetDatabaseNames', function() {
          var res = {};
          Ember.run.later(function() {
            res.onsuccess({
              target: {
                result: [other]
              }
            });
          }, 10);
          return res;
        });
        stub(capabilities.idb, 'deleteDatabase', function(key) {
          deleted_databases.push(key);
        });
        capabilities.setup_database();
      });
    });
  });

  describe("sharing", function() {
    describe('available', function() {
      it('should timeout if sharing types not returned', function() {
        stub(window, 'plugins', {
          socialsharing: {
            canShareVia: function(type, str, header, img, url, success, error) {
            }
          }
        });
        var valids = null;
        capabilities.sharing.available().then(function(list) {
          valids = list;
        });
        waitsFor(function() { return valids; });
        runs(function() {
          expect(valids).toEqual([]);
        });
      });
      it('should return valid sharing types only', function() {
        stub(window, 'cordova', {
          plugins: {
            clipboard: {
              copy: function() { }
            }
          }
        });
        stub(window, 'plugins', {
          socialsharing: {
            canShareVia: function(type, str, header, img, url, success, error) {
              if(type == 'facebook' || type == 'instagram') {
                success();
              } else {
                error();
              }
            }
          }
        });
        var valids = null;
        capabilities.sharing.available().then(function(list) {
          valids = list;
        });
        waitsFor(function() { return valids; });
        runs(function() {
          expect(valids).toEqual(['email', 'generic', 'clipboard', 'facebook', 'instagram']);
        });
      });
    });
    describe('share', function() {
      it('should call correct sharing options', function() {
        var copied_message = null;
        var errored = false;
        var success = false;

        capabilities.sharing.share('clipboard', 'hello', null, null).then(function() {
          success = true;
        }, function() {
          errored = true;
        });
        expect(errored).toEqual(true);
        errored = false; success = false;

        capabilities.sharing.share('email', 'hello', 'http://www.example.com', 'http://www.example.com/image.png').then(function() {
          success = true;
        }, function() {
          errored = true;
        });
        expect(errored).toEqual(true);
        errored = false; success = false;

        stub(window, 'cordova', {
          plugins: { clipboard: { copy: function(str) {
            copied_message = str;
          } } }
        });
        stub(window, 'plugins', {
          socialsharing: {
            shareViaEmail: function(subject, message, a, b, c, url, success, error) {
              success();
            },
            share: function(subject, message, image, url, success, error) {
              error();
            },
            shareVia(app, subject, message, image, url, success, error) {
              if(app == 'facebook') {
                success();
              } else {
                error();
              }
            }
          }
        });

        capabilities.sharing.share('clipboard', 'hello', null, null).then(function() {
          success = true;
        }, function() {
          errored = true;
        });
        expect(success).toEqual(true);
        errored = false; success = false;

        capabilities.sharing.share('email', 'hello', 'http://www.example.com', 'http://www.example.com/image.png').then(function() {
          success = true;
        }, function() {
          errored = true;
        });
        expect(success).toEqual(true);
        errored = false; success = false;

        capabilities.sharing.share('generic', 'hello', 'http://www.example.com', 'http://www.example.com/image.png').then(function() {
          success = true;
        }, function() {
          errored = true;
        });
        expect(success).toEqual(true);
        errored = false; success = false;

        capabilities.sharing.share('facebook', 'hello', 'http://www.example.com', 'http://www.example.com/image.png').then(function() {
          success = true;
        }, function() {
          errored = true;
        });
        expect(success).toEqual(true);
        errored = false; success = false;

        capabilities.sharing.share('instagram', 'hello', 'http://www.example.com', 'http://www.example.com/image.png').then(function() {
          success = true;
        }, function() {
          errored = true;
        });
        expect(success).toEqual(true);
        errored = false; success = false;
      });
    });
  });

  describe("sensors", function() {
    it("should track orientation", function() {
      capabilities.last_orientation = null;
      if(!window.DeviceOrientationEvent) { window.DeviceOrientationEvent = {}; }
      capabilities.sensor_listen();
      var e = new window.CustomEvent('deviceorientation');
      e.alpha = 1;
      e.beta = 2;
      e.gamma = 3;
      window.dispatchEvent(e);
      expect(capabilities.last_orientation.alpha).toEqual(1);
      expect(capabilities.last_orientation.beta).toEqual(2);
      expect(capabilities.last_orientation.gamma).toEqual(3);
      expect(capabilities.last_orientation.layout).toNotEqual(null);
    });

    it('should track volume', function() {
      var callback = null;
      stub(window, 'plugin', {
        volume: {
          setVolumeChangeCallback: function(cb) {
            callback = cb;
          }
        }
      });
      capabilities.last_volume = null;
      capabilities.sensor_listen();
      expect(callback).toNotEqual(null);
      callback(75);
      expect(capabilities.last_volume).toEqual(75);
    });

    it("should track ambient light", function() {
      var callback = null;
      stub(window, 'cordova', {
        exec: function(cb, err, klass, method, args) {
          if(klass == 'CoughDropMisc') {
            callback = cb;
          }
        }
      });
      capabilities.last_lux = null;
      capabilities.sensor_listen();
      waitsFor(function() { return callback; });
      runs(function() {
        callback("1200");
        expect(capabilities.last_lux).toEqual(1200);
      });
    });

    it("should track brightness", function() {
      var callback = null;
      stub(window, 'cordova', {
        plugins: {
          brightness: {
            getBrightness: function(cb) {
              callback = cb;
            }
          }
        }
      });
      capabilities.last_brightness = null;
      capabilities.sensor_listen();
      waitsFor(function() { return callback; });
      runs(function() {
        callback("75");
        expect(capabilities.last_brightness).toEqual(75);
      });
    });

    it("should track ambient light in the browser if possible", function() {
      var sensor = null;
      function LightSensor() {
        this.start = function() { };
        sensor = this;
      }
      stub(window, 'LightSensor', LightSensor);
      capabilities.sensor_listen();
      expect(sensor).toNotEqual(null);
      capabilities.last_lux = null;
      sensor.onchange({reading: {illuminance: 6200}});
      expect(capabilities.last_lux).toEqual(6200);
    });

    it("should track ambient light in the browser if possible with window event", function() {
      capabilities.last_lux = null;
      var e = new window.CustomEvent('devicelight');
      e.lux = 510;
      window.dispatchEvent(e);
      expect(capabilities.last_lux).toEqual(510);
    });
  });

  describe("ssid", function() {
    it("should have specs");
  });
});
