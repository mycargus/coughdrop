import Ember from 'ember';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import { later as runLater } from '@ember/runloop';
import $ from 'jquery';
import RSVP from 'rsvp';
import CoughDrop from '../app';
import stashes from './_stashes';
import session from './session';
import capabilities from './capabilities';

(function() {
  var console_debug = function(str) {
    if(console.debug) {
      console.debug(str);
    } else {
      console.log(str);
    }
  };

  var ready = function(type) {
    ready.types = ready.types || {};
    ready.types[type] = true;
    if(ready.type_callbacks[type]) {
      ready.type_callbacks[type].forEach(function(cb) {
        cb();
      });
      ready.type_callbacks[type] = null;
    }
    if(ready.types.init && ready.types.extras && ready.types.device && !ready.done) {
      ready.done = true;
      ready('all');
      CoughDrop.app.advanceReadiness();
      session.restore();
    }
  };
  ready.watch = function(type, callback) {
    ready.types = ready.types || {};
    ready.type_callbacks = ready.type_callbacks || {};
    if(ready.types[type]) {
      callback();
    } else {
      ready.type_callbacks[type] = ready.type_callbacks[type] || [];
      ready.type_callbacks[type].push(callback);
    }
  };

  var extras = EmberObject.extend({
    setup: function(application) {
      application.register('cough_drop:extras', extras, { instantiate: false, singleton: true });
      $.each(['model', 'controller', 'view', 'route'], function(i, component) {
        application.inject(component, 'extras', 'cough_drop:extras');
      });
    },
    advance: ready,
    enable: function() {
      if(this.get('ready')) { return; }

      console_debug("COUGHDROP: extras ready");
      if(window.app_version) {
        console_debug("COUGHDROP: app version " + window.app_version);
      }
      this.set('ready', true);
      if(window.speechSynthesis) {
        console_debug("COUGHDROP: tts enabled");
      }
      extras.advance('extras');
    },
    storage: {
      find: function(store, key) {
        var defer = RSVP.defer();
        capabilities.invoke({type: 'coughDropExtras', method: 'storage_find', options: {store: store, key: key}}).then(function(res) {
          defer.resolve(res);
        }, function(err) {
          defer.reject(err);
        });
        return defer.promise;
      },
      find_all: function(store, ids) {
        var defer = RSVP.defer();
        capabilities.invoke({type: 'coughDropExtras', method: 'storage_find_all', options: {store: store, ids: ids}}).then(function(res) {
          defer.resolve(res);
        }, function(err) {
          defer.reject(err);
        });
        return defer.promise;
      },
      find_changed: function() {
        var defer = RSVP.defer();
        capabilities.invoke({type: 'coughDropExtras', method: 'storage_find_changed', options: {}}).then(function(res) {
          defer.resolve(res);
        }, function(err) {
          defer.reject(err);
        });
        return defer.promise;
      },
      store: function(store, obj, key) {
        var defer = RSVP.defer();
        capabilities.invoke({type: 'coughDropExtras', method: 'storage_store', options: {store: store, record: obj}}).then(function(res) {
          defer.resolve(res);
        }, function(err) {
          defer.reject(err);
        });
        return defer.promise;
      },
      remove: function(store, id) {
        var defer = RSVP.defer();
        capabilities.invoke({type: 'coughDropExtras', method: 'storage_remove', options: {store: store, record_id: id}}).then(function(res) {
          defer.resolve(res);
        }, function(err) {
          defer.reject(err);
        });
        return defer.promise;
      }
    },
    track_error: function(message) {
      CoughDrop.track_error(message);
    }
  }).create();
  var device_id = stashes.get_raw('coughDropDeviceId');
  if(!device_id) {
    // http://cordova.apache.org/docs/en/6.x/reference/cordova-plugin-device/index.html#deviceuuid
    device_id = (window.device && window.device.uuid) || ((new Date()).getTime() + Math.random()).toString();
    var readable = capabilities.readable_device_name;
    device_id = device_id + " " + readable;
  }
  stashes.persist_raw('coughDropDeviceId', device_id);
  capabilities.device_id = device_id;

  $.realAjax = $.ajax;
  function fakeXHR(xhr) {
    var res = {status: 0};
    if(xhr && xhr.status) {
      var res = {
        readyState: xhr.readyState,
        responseJSON: xhr.responseJSON,
        responseText: xhr.responseText,
        status: xhr.status,
        statusText: xhr.statusText,
      };
      if(xhr.getResponseHeader && xhr.getResponseHeader('BROWSER_TOKEN')) {
        res.browserToken = xhr.getResponseHeader('BROWSER_TOKEN');
      }
    }
    res.getAllResponseHeaders = function() { return null; };
    return res;
  }

  $.ajax = function(opts) {
    var _this = this;
    var args = [];
    var options = arguments[0];
//     var clean_options = {};
    if(typeof(arguments[0]) == 'string') {
      options = arguments[1];
      options.url = options.url || arguments[0];
    }

    var original_options = {}
    for(var key in options) {
      original_options[key] = options[key];
    }
    original_options.attempt = (original_options.attempt || 1);
    if(options.url && options.url.match(/\/api\/v\d+\/boards\/.+%2F.+/)) {
      options.url = options.url.replace(/%2F/, '/');
    }
    if(!options.timeout) {
      if(original_options.attempt <= 1 && options.type == 'GET') {
        options.timeout = 10000;
      } else {
        options.timeout = 20000;
      }
      if(options.type == 'POST' && options.url && options.url.match(/s3\.amazonaws/)) {
        // don't timeout for remote uploads
        options.timeout = null;
      }
    }
//     ['async', 'cache', 'contentType', 'context', 'crossDomain', 'data', 'dataType', 'error', 'global', 'headers', 'ifModified', 'isLocal', 'mimeType', 'processData', 'success', 'timeout', 'type', 'url'].forEach(function(key) {
//       if(options[key]) {
//         clean_options[key] = options[key];
//       }
//     });
//     args.push(clean_options);

    return RSVP.resolve().then(function() {
      var prefix = location.protocol + "//" + location.host;
      if(capabilities.installed_app && capabilities.api_host) {
        prefix = capabilities.api_host;
      }
      if(options.url && options.url.indexOf(prefix) === 0) {
        options.url = options.url.substring(prefix.length);
      }
      if(options.url && options.url.match(/^\//)) {
        if(options.url && options.url.match(/^\/(api\/v\d+\/|token)/) && capabilities.installed_app && capabilities.api_host) {
          options.url = capabilities.api_host + options.url;
        }
        if(capabilities.access_token) {
          options.headers = options.headers || {};
          options.headers['Authorization'] = "Bearer " + capabilities.access_token;
          options.headers['X-Device-Id'] = device_id;
          options.headers['X-CoughDrop-Version'] = window.CoughDrop.VERSION;
        }
        if(CoughDrop.protected_user || stashes.get('protected_user')) {
          options.headers = options.headers || {};
          options.headers['X-SILENCE-LOGGER'] = 'true';
        }
        if(CoughDrop.session && CoughDrop.session.get('as_user_id')) {
          options.headers = options.headers || {};
          options.headers['X-As-User-Id'] = CoughDrop.session.get('as_user_id');
        }
        if(window.ApplicationCache) {
          options.headers = options.headers || {};
          options.headers['X-Has-AppCache'] = "true";
        }
      }

      var success = options.success;
      var error = options.error;
      options.success = null;
      options.error = null;
      var res = $.realAjax(options).then(function(data, message, xhr) {
        if(typeof(data) == 'string') {
          data = {text: data};
        }
        if(data && data.error && data.status && !data.ok) {
          console.log("ember ajax error: " + data.status + ": " + data.error + " (" + options.url + ")");
          if(error) {
            error.call(this, xhr, message, data);
            // The bowels of ember aren't expecting $.ajax to return a real
            // promise and so they don't catch the rejection properly, which
            // potentially causes all sorts of unexpected uncaught errors.
            // NOTE: this means that any CoughDrop code should not use the error parameter
            // if it expects to receive a proper promise.
            // TODO: raise an error somehow if the caller provides an error function
            // and expects a proper promise in response.
            return RSVP.resolve(null);
          } else {
            var rej = RSVP.reject({
              stack: data.status + ": " + data.error + " (" + options.url + ")",
              fakeXHR: fakeXHR(xhr),
              message: message,
              result: data
            });
            rej.then(null, function() { });
            return rej;
           }
        } else {
          if(typeof(data) == 'string') {
          }
          if(data === '' || data === undefined || data === null) {
            data = {};
          }
          data.meta = (data.meta || {});
          data.meta.fakeXHR = fakeXHR(xhr);
          delete data.meta.fakeXHR['responseJSON'];
          $.ajax.meta_push({url: options.url, method: options.type, meta: data.meta});
          if(success) {
            success.call(this, data, message, xhr);
          }
          return data;
        }
      }, function(xhr, message, result) {
        if((result == 'timeout' || result == '') && xhr.status === 0 && xhr.readyState === 0) {
          if((original_options.attempt <= 2 && original_options.type == 'GET') || original_options.attempt <= 1) {
            // try failed GET requests twice, POST/PUT requests once
            original_options.attempt = (original_options.attempt || 1) + 1
            return new RSVP.Promise(function(res, rej) {
              runLater(function() {
                $.ajax(original_options).then(function(r) {
                  res(r);
                }, function(e) {
                  rej(e);
                });
              }, 500);
            });
          }
        }
        if(xhr.responseJSON && xhr.responseJSON.error) {
          result = xhr.responseJSON.error;
        }
        console.log("ember ajax error: " + xhr.status + ": " + result + " (" + options.url + ")");
        if(error) {
          error.call(this, xhr, message, result);
        }
        var rej = RSVP.reject({
          fakeXHR: fakeXHR(xhr),
          message: message,
          result: result
        });
        rej.then(null, function() { });
        return rej;
      });
      res.then(null, function() { });
      return res;
    });
  };
  $.ajax.metas = [];
  $.ajax.meta_push = function(opts) {
    var now = (new Date()).getTime();
    opts.ts = now;

    var metas = $.ajax.metas || [];
    var new_list = [];
    var res = null;
    metas.forEach(function(meta) {
      if(!meta.ts || meta.ts < now - 1000) {
        new_list.push(meta);
      }
    });
    new_list.push(opts);
    $.ajax.metas = new_list;
  };
  $.ajax.meta = function(method, store, id) {
    var res = null;
    var metas = $.ajax.metas || [];
    // TODO: pluralize correctly using same ember library
    var url = "/api/v1/" + store + "s";
    if(capabilities.installed_app && capabilities.api_host) {
      url = capabilities.api_host + url;
    }
    if(id) { url = url + "/" + id; }
    metas.forEach(function(meta) {
      if(meta.method == method && (url == meta.url || (store == meta.model && id == meta.id))) {
        res = meta.meta;
      }
    });
    return res;
  };
  extras.meta = $.ajax.meta;
  extras.meta_push = $.ajax.meta_push;

  window.coughDropExtras = extras;
  extras.advance.watch('device', function() {
    capabilities.invoke({type: 'coughDropExtras', method: 'init'}).then(function(res) {
      extras.enable();
    }, function(err) {
      // TODO: this happens when there is no db, in which case the web site should still
      // work, but we should really keep track of whether extras happened correctly, since
      // it could affect the interface.
      extras.set('offline_available', false);
      extras.enable();
    });
  });

  var status_listener = function(e) {
    var list = [];
    for(var idx in (e.statuses || {})) {
      var name = idx;
      var code = e.statuses[idx].code;
      var dormant = e.statuses[idx].dormant;
      var val = code;
      var active = false;
      var disabled = true;
      if(name == 'eyex') {
        if(code == 2)          { val = "connected";                         disabled = false;
        } else if(code == -1)  { val = "stream init failed";
        } else if(code == 3)   { val = "waiting for data";   active = true; disabled = false;
        } else if(code == 5)   { val = "disconnected";
        } else if(code == 1)   { val = "trying to connect";                 disabled = false;
        } else if(code == -2)  { val = "version too low";
        } else if(code == -3)  { val = "version too high";
        } else if(code == 4)   { val = "data received";      active = true; disabled = false;
        } else if(code == 10)  { val = "initialized";                       disabled = false;
        } else if(code == -10) { val = "init failed";
        } else if(code == -4) { val = "device disconnected";
        } else if(code == -5) { val = "tracking paused";     active = true; disabled = false; dormant = true;
        } else if(code == -6) { val = "user not detected";   active = true; disabled = false; dormant = true;
        }
      } else if(name == 'eyetribe') {
        if(code == 'not_initialized') {
        } else if(code == 'not_tracking') {       active = true; disabled = false;
        } else if(code == 'fully_tracking') {     active = true; disabled = false;
        } else if(code == 'partial_tracking') {   active = true; disabled = false;
        }
      }
      if(e.statuses[idx]) {
        list.push({
          name: name,
          status: val,
          code: code,
          active: active,
          dormant: dormant,
          disabled: disabled
        });
      }
    }
    emberSet(capabilities.eye_gaze, 'statuses', list);
  };
  extras.set('status_listener', status_listener);
  $(document).on('eye-gaze-status', status_listener);
})();

window.time_log = function(str) {
  var stamp = Math.round((((new Date()).getTime() / 1000) % 100) * 100) / 100;
  console.log(str + "  :" + stamp);
};

export default window.coughDropExtras;
