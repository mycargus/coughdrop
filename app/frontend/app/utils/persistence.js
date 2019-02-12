import Ember from 'ember';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import { later as runLater, cancel as runCancel, run } from '@ember/runloop';
import $ from 'jquery';
import RSVP from 'rsvp';
import CoughDrop from '../app';
import coughDropExtras from './extras';
import stashes from './_stashes';
import speecher from './speecher';
import i18n from './i18n';
import contentGrabbers from './content_grabbers';
import Utils from './misc';
import modal from './modal';
import capabilities from './capabilities';

var valid_stores = ['user', 'board', 'image', 'sound', 'settings', 'dataCache', 'buttonset'];
var loaded = (new Date()).getTime() / 1000;
var persistence = EmberObject.extend({
  setup: function(application) {
    application.register('cough_drop:persistence', persistence, { instantiate: false, singleton: true });
    $.each(['model', 'controller', 'view', 'route'], function(i, component) {
      application.inject(component, 'persistence', 'cough_drop:persistence');
    });
    persistence.find('settings', 'lastSync').then(function(res) {
      persistence.set('last_sync_at', res.last_sync);
    }, function() { });
    coughDropExtras.addObserver('ready', function() {
      persistence.find('settings', 'lastSync').then(function(res) {
        persistence.set('last_sync_at', res.last_sync);
      }, function() {
        persistence.set('last_sync_at', 1);
      });
    });
    var ignore_big_log_change = false;
    stashes.addObserver('big_logs', function() {
      if(coughDropExtras && coughDropExtras.ready && !ignore_big_log_change) {
        var rnd_key = (new Date()).getTime() + "_" + Math.random();
        persistence.find('settings', 'bigLogs').then(null, function(err) {
          return RSVP.resvole({});
        }).then(function(res) {
          res = res || {};
          res.logs = res.logs || [];
          var big_logs = (stashes.get('big_logs') || []);
          big_logs.forEach(function(log) {
            res.logs.push(log);
          });
          ignore_big_log_change = rnd_key;
          stashes.set('big_logs', []);
          runLater(function() { if(ignore_big_log_change == rnd_key) { ignore_big_log_change = null; } }, 100);
          persistence.store('settings', res, 'bigLogs').then(function(res) {
          }, function() {
            rnd_key = rnd_key + "2";
            var logs = (stashes.get('big_logs') || []).concat(big_logs);
            ignore_big_log_change = rnd_key;
            stashes.set('big_logs', logs);
            runLater(function() { if(ignore_big_log_change == rnd_key) { ignore_big_log_change = null; } }, 100);
          });
        });
      }
    });
    if(stashes.get_object('just_logged_in', false) && stashes.get('auth_settings') && !Ember.testing) {
      stashes.persist_object('just_logged_in', null, false);
      runLater(function() {
        persistence.check_for_needs_sync(true);
      }, 10 * 1000);
    }
    coughDropExtras.advance.watch('device', function() {
      if(!CoughDrop.ignore_filesystem) {
        capabilities.storage.status().then(function(res) {
          if(res.available && !res.requires_confirmation) {
            res.allowed = true;
          }
          persistence.set('local_system', res);
        });
        runLater(function() {
          persistence.prime_caches().then(null, function() { });
        }, 100);
        runLater(function() {
          if(persistence.get('local_system.allowed')) {
            persistence.prime_caches(true).then(null, function() { });
          }
        }, 2000);
      }
    });
  },
  test: function(method, args) {
    method.apply(this, args).then(function(res) {
      console.log(res);
    }, function() {
      console.error(arguments);
    });
  },
  push_records: function(store, keys) {
    var hash = {};
    var res = {};
    keys.forEach(function(key) { hash[key] = true; });
    CoughDrop.store.peekAll(store).map(function(i) { return i; }).forEach(function(item) {
      if(item) {
        var record = item;
        if(record && hash[record.get('id')]) {
          if(store == 'board' && record.get('permissions') === undefined) {
            // locally-cached board found from a list request doesn't count
          } else {
            hash[record.get('id')] = false;
            res[record.get('id')] = record;
          }
        }
      }
    });
    var any_missing = false;
    keys.forEach(function(key) { if(hash[key] === true) { any_missing = true; } });
    if(any_missing) {
      return new RSVP.Promise(function(resolve, reject) {
        return coughDropExtras.storage.find_all(store, keys).then(function(list) {
          list.forEach(function(item) {
            if(item.data && item.data.id && hash[item.data.id]) {
              hash[item.data.id] = false;
              // Only push to the memory cache if it's not already in
              // there, otherwise it might get overwritten if there
              // is a pending persistence.
              if(CoughDrop.store) {
                var existing = CoughDrop.store.peekRecord(store, item.data.raw.id);
                persistence.validate_board(existing, item.data.raw);
                var json_api = { data: {
                  id: item.data.raw.id,
                  type: store,
                  attributes: item.data.raw
                }};
                if(existing) {
                  res[item.data.id] = existing;
                } else {
                  res[item.data.id] = CoughDrop.store.push(json_api);
                }
              }
            }
          });
          for(var idx in hash) {
            if(hash[idx] === true) {
              persistence.known_missing = persistence.known_missing || {};
              persistence.known_missing[store] = persistence.known_missing[store] || {};
              persistence.known_missing[store][idx] = true;
            }
          }
          resolve(res);
        }, function(err) {
          reject(err);
        });
      });
    } else {
      return RSVP.resolve(res);
    }
  },
  get_important_ids: function() {
    if(persistence.important_ids) {
      return RSVP.resolve(persistence.important_ids);
    } else {
      return coughDropExtras.storage.find('settings', 'importantIds').then(function(res) {
        persistence.important_ids = res.raw.ids || [];
        return persistence.important_ids;
      });
    }
  },
  find: function(store, key, wrapped, already_waited) {
    if(!window.coughDropExtras || !window.coughDropExtras.ready) {
      if(already_waited) {
        return RSVP.reject({error: "extras not ready"});
      } else {
        return new RSVP.Promise(function(resolve, reject) {
          coughDropExtras.advance.watch('all', function() {
            resolve(persistence.find(store, key, wrapped, true));
          });
        });
      }
    }
    if(!key) { /*debugger;*/ }
    return new RSVP.Promise(function(resolve, reject) {
      if(valid_stores.indexOf(store) == -1) {
        reject({error: "invalid type: " + store});
        return;
      }
      if(persistence.known_missing && persistence.known_missing[store] && persistence.known_missing[store][key]) {
//         console.error('found a known missing!');
        reject({error: 'record known missing: ' + store + ' ' + key});
        return;
      }
      var id = RSVP.resolve(key);
      if(store == 'user' && key == 'self') {
        id = coughDropExtras.storage.find('settings', 'selfUserId').then(function(res) {
          return res.raw.id;
        });
      }
      var lookup = id.then(function(id) {
        return coughDropExtras.storage.find(store, id).then(function(record) {
          return persistence.get_important_ids().then(function(ids) {
            return RSVP.resolve({record: record, importantIds: ids});
          }, function(err) {
            // if we've never synced then this will be empty, and that's ok
            if(err && err.error && err.error.match(/no record found/)) {
              return RSVP.resolve({record: record, importantIds: []});
            } else {
              return RSVP.reject({error: "failed to find settings result when querying " + store + ":" + key});
            }
          });
        }, function(err) {
          return RSVP.reject(err);
        });
      });
      lookup.then(function(res) {
        var record = res.record;
        var importantIds = res.importantIds;
        var ago = (new Date()).getTime() - (7 * 24 * 60 * 60 * 1000); // >1 week old is out of date
        // TODO: garbage collection for db??? maybe as part of sync..
        if(record && record.raw) {
          record.raw.important = !!importantIds.find(function(i) { return i == (store + "_" + key); });
        }
        // if we have the opportunity to get it from an online source and it's out of date,
        // we should use the online source
        if(record && record.raw && !record.important && record.persisted < ago) {
          record.raw.outdated = true;
        }

        if(record) {
          var result = {};
          if(wrapped) {
            result[store] = record.raw;
          } else {
            result = record.raw;
          }
          resolve(result);
        } else {
          persistence.known_missing = persistence.known_missing || {};
          persistence.known_missing[store] = persistence.known_missing[store] || {};
          persistence.known_missing[store][key] = true;
          reject({error: "record not found: " + store + ' ' + key});
        }
      }, function(err) {
        persistence.known_missing = persistence.known_missing || {};
        persistence.known_missing[store] = persistence.known_missing[store] || {};
        persistence.known_missing[store][key] = true;
        reject(err);
      });
    });
  },
  remember_access: function(lookup, store, id) {
    if(lookup == 'find' && store == 'board') {
      var recent_boards = stashes.get('recent_boards') || [];
      recent_boards.unshift({id: id});
      var old_list = Utils.uniq(recent_boards.slice(0, 100), function(b) { return !b.id.toString().match(/^tmp_/) ? b.id : null; });
      var key = {};
      var list = [];
      old_list.forEach(function(b) {
        if(!key[b.id]) {
          list.push(b);
        }
      });
      stashes.persist('recent_boards', list);
    }
  },
  find_recent: function(store) {
    return new RSVP.Promise(function(resolve, reject) {
      if(store == 'board') {
        var promises = [];
        var board_ids = [];
        stashes.get('recent_boards').forEach(function(board) {
          board_ids.push(board.id);
        });

        var find_local = coughDropExtras.storage.find_all(store, board_ids).then(function(list) {
          var res = [];
          list.forEach(function(item) {
            if(item.data && item.data.id) {
              // Only push to the memory cache if it's not already in
              // there, otherwise it might get overwritten if there
              // is a pending persistence.
              if(CoughDrop.store) {
                var existing = CoughDrop.store.peekRecord('board', item.data.raw.id);
                if(!existing) {
                  var json_api = { data: {
                    id: item.data.raw.id,
                    type: 'board',
                    attributes: item.data.raw
                  }};
                  res.push(CoughDrop.store.push(json_api));
                } else {
                  res.push(existing);
                }
                persistence.validate_board(existing, item.data.raw);
              }
            }
          });
          return RSVP.resolve(res);
        });
        find_local.then(function(list) {
          resolve(list);
        }, function(err) {
          reject({error: 'find_all failed for ' + store});
        });
      } else {
        reject({error: 'unsupported type: ' + store});
      }
    });
  },
  validate_board: function(board, raw_board) {
    // If the revision hash doesn't match, that means that the model
    // in memory doesn't match what's in the local db.
    // If the model is newer, then there should be a pending storage
    // event persisting it, otherwise something is busted.
    if(board && raw_board) {
      if(board.get('current_revision') != raw_board.current_revision) {
        if(board.get('updated') > raw_board.updated) {
          var eventuals = persistence.eventual_store || [];
          var found_persist = false;
          for(var idx = 0; idx < eventuals.length; idx++) {
            if(eventuals[idx] && eventuals[idx][1] && eventuals[idx][1].id == raw_board.id) {
              found_persist = true;
            }
          }
          if(!found_persist) {
            console.error('lost persistence task for', raw_board.id);
            console.log(board.get('current_revision'), raw_board.current_revision);
          }
        }
      }
    }
  },
  find_changed: function() {
    if(!window.coughDropExtras || !window.coughDropExtras.ready) {
      return RSVP.resolve([]);
    }
    return coughDropExtras.storage.find_changed();
  },
  find_boards: function(str) {
    var re = new RegExp("\\b" + str, 'i');
    var get_important_ids =  coughDropExtras.storage.find('settings', 'importantIds').then(function(res) {
      return RSVP.resolve(res.raw.ids);
    });

    var get_board_ids = get_important_ids.then(function(ids) {
      var board_ids = [];
      ids.forEach(function(id) {
        if(id.match(/^board_/)) {
          board_ids.push(id.replace(/^board_/, ''));
        }
      });
      return board_ids;
    });

    var get_boards = get_board_ids.then(function(ids) {
      var promises = [];
      var boards = [];
      var loaded_boards = CoughDrop.store.peekAll('board');
      ids.forEach(function(id) {
        var loaded_board = loaded_boards.findBy('id', id);
        if(loaded_board) {
          boards.push(loaded_board);
        } else {
          promises.push(persistence.find('board', id).then(function(res) {
            var json_api = { data: {
              id: res.id,
              type: 'board',
              attributes: res
            }};
            var obj = CoughDrop.store.push(json_api);
            boards.push(obj);
            return true;
          }));
        }
      });
      var res = RSVP.all(promises).then(function() {
        return boards;
      });
      promises.forEach(function(p) { p.then(null, function() { }); });
      return res;
    });

    var search_boards = get_boards.then(function(boards) {
      var matching_boards = [];
      boards.forEach(function(board) {
        var str = board.get('key') + " " + board.get('name') + " " + board.get('description');
        (board.get('buttons') || []).forEach(function(button) {
          str = str + " " + (button.label || button.vocalization);
        });
        if(str.match(re)) {
          matching_boards.push(board);
        }
      });
      return matching_boards;
    });

    return search_boards;
  },
  remove: function(store, obj, key, log_removal) {
    var _this = this;
    this.removals = this.removals || [];
    if(window.coughDropExtras && window.coughDropExtras.ready) {
      runLater(function() {
        var record = obj[store] || obj;
        record.id = record.id || key;
        var result = coughDropExtras.storage.remove(store, record.id).then(function() {
          return RSVP.resolve(obj);
        }, function(error) {
          return RSVP.reject(error);
        });

        if(log_removal) {
          result = result.then(function() {
            return coughDropExtras.storage.store('deletion', {store: store, id: record.id, storageId: (store + "_" + record.id)});
          });
        }

        result.then(function() {
          persistence.log = persistence.log || [];
          persistence.log.push({message: "Successfully removed object", object: obj, key: key});
          _this.removals.push({id: record.id});
        }, function(error) {
          persistence.errors = persistence.errors || [];
          persistence.errors.push({error: error, message: "Failed to remove object", object: obj, key: key});
        });
      }, 30);
    }

    return RSVP.resolve(obj);
  },
  store_eventually: function(store, obj, key) {
    persistence.eventual_store = persistence.eventual_store || [];
    persistence.eventual_store.push([store, obj, key, true]);
    if(!persistence.eventual_store_timer) {
      persistence.eventual_store_timer = runLater(persistence, persistence.next_eventual_store, 100);
    }
    return RSVP.resolve(obj);
  },
  refresh_after_eventual_stores: function() {
    if(persistence.eventual_store && persistence.eventual_store.length > 0) {
      persistence.refresh_after_eventual_stores.waiting = true;
    } else {
      // TODO: I can't figure out a reliable way to know for sure
      // when all the records can be looked up in the local store,
      // so I'm using timers for now. Luckily these lookups shouldn't
      // be very involved, especially once the record has been found.
      if(CoughDrop.Board) {
        runLater(CoughDrop.Board.refresh_data_urls, 2000);
      }
    }
  },
  next_eventual_store: function() {
    if(persistence.eventual_store_timer) {
      runCancel(persistence.eventual_store_timer);
    }
    try {
      var args = (persistence.eventual_store || []).shift();
      if(args) {
        persistence.store.apply(persistence, args);
      } else if(persistence.refresh_after_eventual_stores.waiting) {
        persistence.refresh_after_eventual_stores.waiting = false;
        if(CoughDrop.Board) {
          CoughDrop.Board.refresh_data_urls();
        }
      }
    } catch(e) { }
    persistence.eventual_store_timer = runLater(persistence, persistence.next_eventual_store, 200);
  },
  store: function(store, obj, key, eventually) {
    // TODO: more nuanced wipe of known_missing would be more efficient
    persistence.known_missing = persistence.known_missing || {};
    persistence.known_missing[store] = {};

    var _this = this;

    return new RSVP.Promise(function(resolve, reject) {
      if(coughDropExtras && coughDropExtras.ready) {
        persistence.stores = persistence.stores || [];
        var promises = [];
        var store_method = eventually ? persistence.store_eventually : persistence.store;
        if(valid_stores.indexOf(store) != -1) {
          var record = {raw: (obj[store] || obj)};
          if(store == 'settings') {
            record.storageId = key;
          }
          if(store == 'user') {
            record.raw.key = record.raw.user_name;
          }
          record.id = record.raw.id || key;
          record.key = record.raw.key;
          record.tmp_key = record.raw.tmp_key;
          record.changed = !!record.raw.changed;


          var store_promise = coughDropExtras.storage.store(store, record, key).then(function() {
            if(store == 'user' && key == 'self') {
              return store_method('settings', {id: record.id}, 'selfUserId').then(function() {
                return RSVP.resolve(record.raw);
              }, function() {
                return RSVP.reject({error: "selfUserId not persisted"});
              });
            } else {
              return RSVP.resolve(record.raw);
            }
          });
          store_promise.then(null, function() { });
          promises.push(store_promise);
        }
        if(store == 'board' && obj.images) {
          obj.images.forEach(function(img) {
            promises.push(store_method('image', img, null));
          });
        }
        if(store == 'board' && obj.sounds) {
          obj.sounds.forEach(function(snd) {
            promises.push(store_method('sound', snd, null));
          });
        }
        RSVP.all(promises).then(function() {
          persistence.known_missing = persistence.known_missing || {};
          persistence.known_missing[store] = {};
          persistence.stores.push({object: obj});
          persistence.log = persistence.log || [];
          persistence.log.push({message: "Successfully stored object", object: obj, store: store, key: key});
        }, function(error) {
          persistence.errors = persistence.errors || [];
          persistence.errors.push({error: error, message: "Failed to store object", object: obj, store: store, key: key});
        });
        promises.forEach(function(p) { p.then(null, function() { }); });
      }

      resolve(obj);
    });
  },
  normalize_url: function(url) {
    if(url && url.match(/user_token=[\w-]+$/)) {
      return url.replace(/[\?\&]user_token=[\w-]+$/, '');
    } else {
      return url;
    }
  },
  find_url: function(url, type) {
    if(!this.primed) {
      var _this = this;
      return new RSVP.Promise(function(res, rej) {
        runLater(function() {
          _this.find_url(url, type).then(function(r) { res(r); }, function(e) { rej(e); });
        }, 500);
      });
    }
    url = this.normalize_url(url);
    // url_cache is a cache of all images that already have a data-uri loaded
    // url_uncache is all images that are known to not have a data-uri loaded
    if(this.url_cache && this.url_cache[url]) {
      return RSVP.resolve(this.url_cache[url]);
    } else if(this.url_uncache && this.url_uncache[url]) {
      var _this = this;
      var find = this.find('dataCache', url);
      return find.then(function(data) {
        _this.url_cache = _this.url_cache || {};
        var file_missing = _this.url_cache[url] === false;
        if(data.local_url) {
          if(data.local_filename) {
            if(type == 'image' && _this.image_filename_cache && _this.image_filename_cache[data.local_filename]) {
              _this.url_cache[url] = capabilities.storage.fix_url(data.local_url);
              return _this.url_cache[url];
            } else if(type == 'sound' && _this.sound_filename_cache && _this.sound_filename_cache[data.local_filename]) {
              _this.url_cache[url] = capabilities.storage.fix_url(data.local_url);
              return _this.url_cache[url];
            } else {
              // confirm that the file is where it's supposed to be before returning
              return new RSVP.Promise(function(file_url_resolve, file_url_reject) {
                // apparently file system calls are really slow on ios
                if(data.local_url) {
                  var local_url = capabilities.storage.fix_url(data.local_url);
                  _this.url_cache[url] = local_url;
                  file_url_resolve(local_url);
                } else {
                  if(file_missing) {
                    capabilities.storage.get_file_url(type, data.local_filename).then(function(local_url) {
                      var local_url = capabilities.storage.fix_url(local_url);
                      _this.url_cache[url] = local_url;
                      file_url_resolve(local_url);
                    }, function() {
                      if(data.data_uri) {
                        file_url_resolve(data.data_uri);
                      } else {
                        file_url_reject({error: "missing local file"});
                      }
                    });
                  } else {
                    var local_url = capabilities.storage.fix_url(data.local_filename);
                    _this.url_cache[url] = local_url;
                    file_url_resolve(local_url);
                  }
                }
              });
            }
          }
          data.local_url = capabilities.storage.fix_url(data.local_url);
          _this.url_cache[url] = data.local_url;
          return data.local_url || data.data_uri;
        } else if(data.data_uri) {
          // methinks caching data URIs would fill up memory mighty quick, so let's not cache
          return data.data_uri;
        } else {
          return RSVP.reject({error: "no data URI or filename found for cached URL"});
        }
      });
    } else {
      return RSVP.reject({error: 'url not in storage'});
    }
  },
  prime_caches: function(check_file_system) {
    var _this = this;
    _this.url_cache = _this.url_cache || {};
    _this.url_uncache = _this.url_uncache || {};
    _this.image_filename_cache = _this.image_filename_cache || {};
    _this.sound_filename_cache = _this.sound_filename_cache || {};

    var prime_promises = [];
    if(_this.get('local_system.available') && _this.get('local_system.allowed') && stashes.get('auth_settings')) {
    } else {
      _this.primed = true;
      return RSVP.reject({error: 'not enabled or no user set'});
    }
    runLater(function() {
      if(!_this.primed) { _this.primed = true; }
    }, 10000);

    prime_promises.push(new RSVP.Promise(function(res, rej) {
      // apparently file system calls are really slow on ios
      if(!check_file_system) { return res([]); }
      capabilities.storage.list_files('image').then(function(images) {
        images.forEach(function(image) {
          _this.image_filename_cache[image] = true;
        });
        res(images);
      }, function(err) { rej(err); });
    }));
    prime_promises.push(new RSVP.Promise(function(res, rej) {
      // apparently file system calls are really slow on ios
      if(!check_file_system) { return res([]); }
      capabilities.storage.list_files('sound').then(function(sounds) {
        sounds.forEach(function(sound) {
          _this.sound_filename_cache[sound] = true;
        });
        res(sounds);
      }, function(err) { rej(err); });
    }));
    var res = RSVP.all_wait(prime_promises).then(function() {
      return coughDropExtras.storage.find_all('dataCache').then(function(list) {
        var promises = [];
        list.forEach(function(item) {
          if(item.data && item.data.raw && item.data.raw.url && item.data.raw.type && item.data.raw.local_filename) {
            _this.url_cache[item.data.raw.url] = null;
            _this.url_uncache[item.data.raw.url] = null;
            // if the image is found in the local directory listing, it's good
            if(item.data.raw.type == 'image' && item.data.raw.local_url && _this.image_filename_cache && _this.image_filename_cache[item.data.raw.local_filename]) {
              _this.url_cache[item.data.raw.url] = capabilities.storage.fix_url(item.data.raw.local_url);
            // if the sound is found in the local directory listing, it's good
            } else if(item.data.raw.type == 'sound' && item.data.raw.local_url && _this.sound_filename_cache && _this.sound_filename_cache[item.data.raw.local_filename]) {
              _this.url_cache[item.data.raw.url] = capabilities.storage.fix_url(item.data.raw.local_url);
            } else {
              // apparently file system calls are really slow on ios (and android), so we skip for the first go-round
              // (fix_url compensates for directory structures changing on ios with updates)
              if(!check_file_system) {
                _this.url_cache[item.data.raw.url] = capabilities.storage.fix_url(item.data.raw.local_url);
              } else {
                promises.push(new RSVP.Promise(function(res, rej) {
                  // see if it's available as a file_url since it wasn't in the directory listing
                  capabilities.storage.get_file_url(item.data.raw.type, item.data.raw.local_filename).then(function(local_url) {
                    local_url = capabilities.storage.fix_url(local_url);
                    _this.url_cache[item.data.raw.url] = local_url;
                    res(local_url);
                  }, function(err) {
                    _this.url_cache[item.data.raw.url] = false;
                    rej(err);
                  });
                }));
              }
            }
          // if no local_filename defined, then it's known to not be cached
          } else if(item.data && item.data.raw && item.data.raw.url) {
            _this.url_uncache[item.data.raw.url] = true;
          }
        });
        return RSVP.all_wait(promises).then(function() {
          return list;
        });
      });
    });
//     if(!_this.primed && capabilities.mobile && false) {
//       // css preload of all images on mobile
//       var style = document.createElement('style');
//       style.type = 'text/css';
//       var head = document.getElementsByTagName('head')[0];
//       var rules = [];
//       for(var idx in _this.url_cache) {
//         rules.push("url(\"" + _this.url_cache[idx] + "\")");
//       }
//       style.innerHTML = 'body::after { content: ' + (rules.join(' ')) + '; height: 0; position: absolute; left: -1000;}';
//       if(head) {
//         head.appendChild(style);
//       }
//     }
    res.then(function() { _this.primed = true; }, function() { _this.primed = true; });
    return res;
  },
  url_cache: {},
  store_url: function store_url(url, type, keep_big, force_reload, sync_id) {
    persistence.urls_to_store = persistence.urls_to_store || [];
    var defer = RSVP.defer();
    var opts = {
      url: url,
      type: type,
      keep_big: keep_big,
      force_reload: force_reload,
      sync_id: sync_id,
      defer: defer
    };
    persistence.urls_to_store.push(opts);
    if(!persistence.storing_urls) {
      persistence.storing_url_watchers = 0;
      persistence.storing_urls = function() {
        if(persistence.urls_to_store && persistence.urls_to_store.length > 0) {
          var opts = persistence.urls_to_store.shift();
          var part_of_canceled = opts.sync_id && (!persistence.get('sync_progress') || persistence.get('sync_progress.canceled'));
          if(!part_of_canceled) {
            persistence.store_url_now(opts.url, opts.type, opts.keep_big, opts.force_reload).then(function(res) {
              opts.defer.resolve(res);
              if(persistence.storing_urls) { persistence.storing_urls(); }
            }, function(err) {
              opts.defer.reject(err);
              if(persistence.storing_urls) { persistence.storing_urls(); }
            });
          } else {
            opts.defer.reject({error: 'sync canceled'});
          }
        } else {
          persistence.storing_url_watchers--;
        }
      };
    }
    var max_watchers = 3;
    if(capabilities.mobile) {
      max_watchers = 2;
      if(capabilities.system == 'Android') {
        max_watchers = 1;
      }
    }
    if(persistence.storing_url_watchers < max_watchers) {
      persistence.storing_url_watchers++;
      persistence.storing_urls();
    }
    return defer.promise;
  },
  store_url_now: function(url, type, keep_big, force_reload) {
    if(!type) { return RSVP.reject('type required for storing'); }
    if(!url) { console.error('url not provided'); return RSVP.reject('url required for storing'); }
    if(!window.coughDropExtras || !window.coughDropExtras.ready || url.match(/^data:/) || url.match(/^file:/)) {
      return RSVP.resolve({
        url: url,
        type: type
      });
    }

    var url_id = persistence.normalize_url(url);
    var _this = persistence;
    return new RSVP.Promise(function(resolve, reject) {
      var lookup = RSVP.reject();

      var trusted_not_to_change = url.match(/opensymbols\.s3\.amazonaws\.com/) || url.match(/s3\.amazonaws\.com\/opensymbols/) ||
                  url.match(/coughdrop-usercontent\.s3\.amazonaws\.com/) || url.match(/s3\.amazonaws\.com\/coughdrop-usercontent/) ||
                  url.match(/d18vdu4p71yql0.cloudfront.net/) || url.match(/dc5pvf6xvgi7y.cloudfront.net/);
      var cors_match = trusted_not_to_change || url.match(/api\/v\d+\/users\/.+\/protected_image/);
      var check_for_local = !!trusted_not_to_change;

      if(capabilities.installed_app) { check_for_local = true; }
      if(check_for_local) {
        // skip the remote request if it's stored locally from a location we
        // know won't ever modify static assets
        lookup = lookup.then(null, function() {
          return persistence.find('dataCache', url_id).then(function(data) {
            // if it's a manual sync, always re-download untrusted resources
            if(force_reload && !trusted_not_to_change) {
              return RSVP.reject();
            // if we think it's stored locally but it's not in the cache, it needs to be repaired
            } else if(_this.url_cache && _this.url_cache[url] && (!_this.url_uncache || !_this.url_uncache[url])) {
              return RSVP.resolve(data);
            } else {
              return RSVP.reject();
            }
          });
        });
      }

      if(cors_match && window.FormData) {
        // try avoiding the proxy if we know the resource is CORS-enabled. Have to fall
        // back to plain xhr in order to get blob response
        lookup = lookup.then(null, function() {
          return new RSVP.Promise(function(xhr_resolve, xhr_reject) {
            var xhr = new XMLHttpRequest();
            xhr.addEventListener('load', function(r) {
              if(xhr.status == 200) {
                contentGrabbers.read_file(xhr.response).then(function(s) {
                  xhr_resolve({
                    url: url,
                    type: type,
                    content_type: xhr.getResponseHeader('Content-Type'),
                    data_uri: s.target.result
                  });
                }, function() {
                  xhr_reject({cors: true, error: 'URL processing failed'});
                });
              } else {
                console.log("COUGHDROP: CORS request probably failed");
                xhr_reject({cors: true, error: 'URL lookup failed with ' + xhr.status});
              }
            });
            xhr.addEventListener('error', function() {
              xhr_reject({cors: true, error: 'URL lookup error'});
            });
            xhr.addEventListener('abort', function() { xhr_reject({cors: true, error: 'URL lookup aborted'}); });
//            console.log("trying CORS request for " + url);
            // Adding the query parameter because I suspect that if a URL has already
            // been retrieved by the browser, it's not sending CORS headers on the
            // follow-up request, maybe?
            xhr.open('GET', url + (url.match(/\?/) ? '&' : '?') + "cr=1");
            xhr.responseType = 'blob';
            xhr.send(null);
          });
        });
      }

      var fallback = lookup.then(null, function(res) {
        if(res && res.error && res.cors) {
          console.error("CORS request error: " + res.error);
        }
        var external_proxy = RSVP.reject();
        if(window.symbol_proxy_key) {
          external_proxy = persistence.ajax('https://www.opensymbols.org/api/v1/symbols/proxy?url=' + encodeURIComponent(url) + '&access_token=' + window.symbol_proxy_key, {type: 'GET'}).then(function(data) {
            var object = {
              url: url,
              type: type,
              content_type: data.content_type,
              data_uri: data.data
            };
            return RSVP.resolve(object);
          });
        }
        return external_proxy.then(null, function() {
          return persistence.ajax('/api/v1/search/proxy?url=' + encodeURIComponent(url), {type: 'GET'}).then(function(data) {
            var object = {
              url: url,
              type: type,
              content_type: data.content_type,
              data_uri: data.data
            };
            return RSVP.resolve(object);
          }, function(xhr) {
            reject({error: "URL lookup failed during proxy for " + url});
          });
        });
      });

      var size_image = fallback.then(function(object) {
        // don't resize already-saved images, non-images, or required-to-be-big images
        if(object.persisted || type != 'image' || capabilities.system != "Android" || keep_big) {
          return object;
        } else {
          return contentGrabbers.pictureGrabber.size_image(object.url, 50).then(function(res) {
            if(res.url && res.url.match(/^data/)) {
              object.data_uri = res.url;
              object.content_type = (res.url.split(/:/)[1] || "").split(/;/)[0] || "image/png";
            }
            return object;
          }, function() {
            return RSVP.resolve(object);
          });
        }
      });

      size_image.then(function(object) {
        // remember: persisted objects will not have a data_uri attribute, so this will be skipped for them
        if(persistence.get('local_system.available') && persistence.get('local_system.allowed') && stashes.get('auth_settings')) {
          if(object.data_uri) {
            var local_system_filename = object.local_filename;
            if(!local_system_filename) {
              var file_code = 0;
              for(var idx = 0; idx < url.length; idx++) { file_code = file_code + url.charCodeAt(idx); }
              var pieces = url.split(/\?/)[0].split(/\//);
              var extension = contentGrabbers.file_type_extensions[object.content_type];
              if(!extension) {
                if(object.content_type.match(/^image\//) || object.content_type.match(/^audio\//)) {
                  extension = "." + object.content_type.split(/\//)[1].split(/\+/)[0];
                }
              }
              var url_extension = pieces[pieces.length - 1].split(/\./).pop();
              if(!extension && url_extension) {
                extension = "." + url_extension;
              }
              var url_piece = pieces.pop();
              if(url_piece.length > 20) {
                url_piece = url_piece.substring(0, 20);
              }
              extension = extension || ".png";
              local_system_filename = (file_code % 10000).toString() + "0000." + url_piece + "." + file_code.toString() + extension;
            }
            var svg = null;
            if(object.data_uri.match(/svg/)) {
              try {
                svg = atob(object.data_uri.split(/,/)[1]);
                if((svg.match(/<svg/) || []).length > 1) { console.error('data_uri had double-content'); }
              } catch(e) { }
            }
            return new RSVP.Promise(function(write_resolve, write_reject) {
              var blob = contentGrabbers.data_uri_to_blob(object.data_uri);
              if(svg && blob.size > svg.length) { console.error('blob generation caused double-content'); }
              capabilities.storage.write_file(type, local_system_filename, blob).then(function(res) {
                object.data_uri = null;
                object.local_filename = local_system_filename;
                object.local_url = res;
                object.persisted = true;
                object.url = url_id;
                write_resolve(persistence.store('dataCache', object, object.url));
              }, function(err) { write_reject(err); });
            });
          } else {
            return object;
          }
        } else {
          if(!object.persisted) {
            object.persisted = true;
            object.url = url_id;
            return persistence.store('dataCache', object, object.url);
          } else {
            return object;
          }
        }
      }).then(function(object) {
        persistence.url_cache = persistence.url_cache || {};
        persistence.url_uncache = persistence.url_uncache || {};
        if(object.local_url) {
          persistence.url_cache[url_id] = capabilities.storage.fix_url(object.local_url);
          persistence.url_uncache[url_id] = false;
        } else {
          persistence.url_uncache[url_id] = true;
        }

        resolve(object);
      }, function(err) {
        persistence.url_uncache = persistence.url_uncache || {};
        persistence.url_uncache[url_id] = true;
        var error = {error: "saving to data cache failed"};
        if(err && err.name == "QuotaExceededError") {
          error.quota_maxed = true;
        }
        reject(error);
      });
    });
  },
  enable_wakelock: function() {
    if(this.get('syncing')) {
      capabilities.wakelock('sync', true);
    } else {
      capabilities.wakelock('sync', false);
    }
  }.observes('syncing'),
  syncing: function() {
    return this.get('sync_status') == 'syncing';
  }.property('sync_status'),
  sync_failed: function() {
    return this.get('sync_status') == 'failed';
  }.property('sync_status'),
  sync_succeeded: function() {
    return this.get('sync_status') == 'succeeded';
  }.property('sync_status'),
  sync_finished: function() {
    return this.get('sync_status') == 'finished';
  }.property('sync_status'),
  update_sync_progress: function() {
    var progresses = (persistence.get('sync_progress') || {}).progress_for || {};
    var visited = 0;
    var to_visit = 0;
    var errors = [];
    for(var idx in progresses) {
      visited = visited + progresses[idx].visited;
      to_visit = to_visit + progresses[idx].to_visit;
      errors = errors.concat(progresses[idx].board_errors || []);
    }
    if(persistence.get('sync_progress')) {
      persistence.set('sync_progress.visited', visited);
      persistence.set('sync_progress.to_visit', to_visit);
      persistence.set('sync_progress.total', to_visit + visited);
      persistence.set('sync_progress.errored', errors.length);
      persistence.set('sync_progress.errors', errors);
    }
  },
  cancel_sync: function() {
    if(persistence.get('sync_progress')) {
      persistence.set('sync_progress.canceled', true);
    }
  },
  sync: function(user_id, force, ignore_supervisees) {
    if(!window.coughDropExtras || !window.coughDropExtras.ready) {
      return new RSVP.Promise(function(wait_resolve, wait_reject) {
        coughDropExtras.advance.watch('all', function() {
          wait_resolve(persistence.sync(user_id, force, ignore_supervisees));
        });
      });
    }

    console.log('syncing for ' + user_id);
    var user_name = user_id;
    if(this.get('online')) {
      stashes.push_log();
      stashes.track_daily_use();
    }
    persistence.set('last_sync_event_at', (new Date()).getTime());

    this.set('sync_status', 'syncing');
    var synced_boards = [];
    // TODO: this could move to bg.js, that way it can run in the background
    // even if the app itself isn't running. whaaaat?! yeah.

    var sync_promise = new RSVP.Promise(function(sync_resolve, sync_reject) {
      if(!persistence.get('sync_progress.root_user')) {
        persistence.set('sync_progress', {
          root_user: user_id,
          progress_for: {
          }
        });
      }

      if(!user_id) {
        sync_reject({error: "failed to retrieve user, missing id"});
      }

      var prime_caches = persistence.prime_caches(true).then(null, function() { return RSVP.resolve(); });

      var check_first = function(callback) {
        if(!persistence.get('sync_progress') || persistence.get('sync_progress.canceled')) {
          return function() {
            return RSVP.reject({error: 'canceled'});
          };
        } else {
          return callback;
        }
      };

      var find_user = prime_caches.then(check_first(function() {
        return CoughDrop.store.findRecord('user', user_id).then(function(user) {
          return user.reload().then(null, function() {
            sync_reject({error: "failed to retrieve user details"});
          });
        }, function() {
          sync_reject({error: "failed to retrieve user details"});
        });
      }));

      // cache images used for keyboard spelling to work offline
      if(!CoughDrop.testing || CoughDrop.sync_testing) {
        persistence.store_url('https://s3.amazonaws.com/opensymbols/libraries/mulberry/pencil%20and%20paper%202.svg', 'image', false, false).then(null, function() { });
        persistence.store_url('https://s3.amazonaws.com/opensymbols/libraries/mulberry/paper.svg', 'image', false, false).then(null, function() { });
        persistence.store_url('https://s3.amazonaws.com/opensymbols/libraries/arasaac/board_3.png', 'image', false, false).then(null, function() { });
      }

      var confirm_quota_for_user = find_user.then(check_first(function(user) {
        if(user) {
          persistence.set('online', true);
          if(user.get('preferences.skip_supervisee_sync')) {
            ignore_supervisees = true;
          }
          user_name = user.get('user_name') || user_id;
          if(persistence.get('local_system.available') && user.get('preferences.home_board') &&
                    !persistence.get('local_system.allowed') && persistence.get('local_system.requires_confirmation') &&
                    stashes.get('allow_local_filesystem_request')) {
            return new RSVP.Promise(function(check_resolve, check_reject) {
              capabilities.storage.root_entry().then(function() {
                persistence.set('local_system.allowed', true);
                check_resolve(user);
              }, function() {
                persistence.set('local_system.available', false);
                persistence.set('local_system.allowed', false);
                check_resolve(user);
              });
            });
          }
        }
        return user;
      }));

      confirm_quota_for_user.then(check_first(function(user) {
        if(user) {
          var old_user_id = user_id;
          user_id = user.get('id');
          if(!persistence.get('sync_progress.root_user') || persistence.get('sync_progress.root_user') == old_user_id) {
            persistence.set('sync_progress', {
              root_user: user.get('id'),
              progress_for: {
              }
            });
          }
        }
        // TODO: also download all the user's personally-created boards

        var sync_log = [];

        var sync_promises = [];

        // Step 0: If extras isn't ready then there's nothing else to do
        if(!window.coughDropExtras || !window.coughDropExtras.ready) {
          sync_promises.push(RSVP.reject({error: "extras not ready"}));
        }
        if(!capabilities.db) {
          sync_promises.push(RSVP.reject({error: "db not initialized"}));
        }

        // Step 0.5: Check for an invalidated token
        if(CoughDrop.session && !CoughDrop.session.get('invalid_token')) {
          if(persistence.get('sync_progress.root_user') == user_id) {
            CoughDrop.session.check_token(false);
          }
        }

        // Step 1: If online
        // if there are any pending transactions, save them one by one
        // (needs to also support s3 uploading for locally-saved images/sounds)
        // (needs to be smart about handling conflicts)
        // http://www.cs.tufts.edu/~nr/pubs/sync.pdf
        if(persistence.get('sync_progress.root_user') == user_id) {
          sync_promises.push(persistence.sync_changed());
        }

        var importantIds = [];

        // Step 2: If online
        // get the latest user profile information and settings
        sync_promises.push(persistence.sync_user(user, importantIds));

        // Step 3: If online
        // check if the board set has changed at all, and if so
        // (or force == true) pull it all down locally
        // (add to settings.importantIds list)
        // (also download through proxy any image data URIs needed for board set)
        var get_local_revisions = persistence.find('settings', 'synced_full_set_revisions').then(function(res) {
          if(persistence.get('sync_progress') && !persistence.get('sync_progress.full_set_revisions')) {
            persistence.set('sync_progress.full_set_revisions', res);
          }
          return persistence.sync_boards(user, importantIds, synced_boards, force);
        }, function() {
          return persistence.sync_boards(user, importantIds, synced_boards, force);
        });
        sync_promises.push(get_local_revisions);
          

        // Step 4: If user has any supervisees, sync them as well
        if(user && user.get('supervisees') && !ignore_supervisees) {
          sync_promises.push(persistence.sync_supervisees(user, force));
        }

        // Step 5: Cache needed sound files
        sync_promises.push(speecher.load_beep());

        // Step 6: Push stored logs
        sync_promises.push(persistence.sync_logs(user));

        // Step 7: Sync user tags
        sync_promises.push(persistence.sync_tags(user));

        // reject on any errors
        RSVP.all_wait(sync_promises).then(function() {
          // Step 4: If online
          // store the list ids to settings.importantIds so they don't get expired
          // even after being offline for a long time. Also store lastSync somewhere
          // that's easy to get to (localStorage much?) for use in the interface.
          persistence.important_ids = importantIds.uniq();
          persistence.store('settings', {ids: persistence.important_ids}, 'importantIds').then(function(r) {
            persistence.refresh_after_eventual_stores();
            sync_resolve(sync_log);
          }, function() {
            persistence.refresh_after_eventual_stores();
            sync_reject(arguments);
          });
        }, function() {
          persistence.refresh_after_eventual_stores();
          sync_reject.apply(null, arguments);
        });
      }));

    }).then(function() {
      // TODO: some kind of alert with a "reload" option, since we potentially
      // just changed data out from underneath what's showing in the UI

      // make a list of all buttons in the set so we can figure out the button
      // sequence needed to get from A to B
      var track_buttons = persistence.sync_buttons(synced_boards);

      var complete_sync = track_buttons.then(function() {
        var last_sync = (new Date()).getTime() / 1000;
        if(persistence.get('sync_progress.root_user') == user_id) {
          var statuses = persistence.get('sync_progress.board_statuses') || [];
          if(persistence.get('sync_progress.last_sync_stamp')) {
            persistence.set('last_sync_stamp', persistence.get('sync_progress.last_sync_stamp'));
          }
          var errors = persistence.get('sync_progress.errors') || [];
          errors.forEach(function(error) {
            if(error.board_key || error.board_id) {
              var status = statuses.find(function(s) { return (s.key && s.key == error.board_key); });
              if(status) {
                status.error = error.error;
              } else {
                statuses.push({
                  id: error.board_id || error.board_key,
                  key: error.board_key || error.board_id,
                  error: error.error
                });
              }
            }
          });
          persistence.set('sync_progress', null);
          var sync_message = null;
          if(errors.length > 0) {
            persistence.set('sync_status', 'finished');
            persistence.set('sync_errors', errors.length);
            sync_message = i18n.t('finished_with_errors', "Finished syncing %{user_id} with %{n} error(s)", {user_id: user_name, n: errors.length});
          } else {
            persistence.set('sync_status', 'succeeded');
            sync_message = i18n.t('finised_without_errors', "Finished syncing %{user_id} without errors", {user_id: user_name});
          }
          console.log('synced!');
          persistence.store('settings', {last_sync: last_sync}, 'lastSync').then(function(res) {
            persistence.set('last_sync_at', res.last_sync);
            persistence.set('last_sync_event_at', (new Date()).getTime());
          }, function() {
            debugger;
          });
          var log = [].concat(persistence.get('sync_log') || []);
          log.push({
            user_id: user_name,
            manual: force,
            issues: errors.length > 0,
            finished: new Date(),
            statuses: statuses,
            summary: sync_message
          });
          persistence.set('sync_log', log);
          persistence.set('sync_log_rand', Math.random());
        }
        return RSVP.resolve(last_sync);
      });
      return complete_sync;
    }, function(err) {
      if(persistence.get('sync_progress.root_user') == user_id) {
        var statuses = persistence.get('sync_progress.board_statuses') || [];
        persistence.set('sync_progress', null);
        persistence.set('sync_status', 'failed');
        persistence.set('sync_status_error', null);
        if(err.board_unauthorized) {
          persistence.set('sync_status_error', i18n.t('board_unauthorized', "One or more boards are private"));
        } else if(!persistence.get('online')) {
          persistence.set('sync_status_error', i18n.t('not_online', "Must be online to sync"));
        }
        var message = (err && err.error) || "unspecified sync error";
        var statuses = statuses.uniq(function(s) { return s.id; });
        var log = [].concat(persistence.get('sync_log') || []);
        log.push({
          user_id: user_name,
          manual: force,
          errored: true,
          finished: new Date(),
          statuses: statuses,
          summary: i18n.t('finised_without_errors', "Error syncing %{user_id}: ", {user_id: user_name}) + message
        });
        persistence.set('last_sync_event_at', (new Date()).getTime());
        persistence.set('sync_log', log);
        if(err && err.error) {
          modal.error(err.error);
        }
        console.log(err);
      }
      return RSVP.reject(err);
    });
    this.set('sync_promise', sync_promise);
    return sync_promise;
  },
  sync_tags: function(user) {
    return RSVP.new(function(resolve, reject) {
      var tag_ids = user.get('preferences.tag_ids') || [];
      var next_tag = function() {
        var tag_id = tag_ids.pop();
        if(tag_id) {
          persistence.findRecord('tag', tag_id).then(function(tag) {
            if(tag.get('button.image_url')) {
              persistence.store_url(tag.get('button.image_url'), 'image', false, false).then(function() {
                runLater(next_tag, 500);
              }, function() {
                runLater(next_tag, 500);
                // TODO: handle tag storage errors as warnings, not failures
              });
            } else {
              runLater(next_tag, 500);
            }
          }, function(err) {
            runLater(next_tag, 500);
            // TODO: handle tag storage errors as warnings, not failures
          });
        } else {
          resolve();
        }
      };
      runLater(next_tag, 500);
    });
  },
  sync_logs: function(user) {
    return persistence.find('settings', 'bigLogs').then(function(res) {
      res = res || {};
      var fails = [];
      var log_promises = [];
      (res.logs || []).forEach(function(data) {
        var log = CoughDrop.store.createRecord('log', {
          events: data
        });
        log.cleanup();
        log_promises.push(log.save().then(null, function(err) {
          fails.push(data);
          return RSVP.reject({error: 'log failed to save'});
        }));
      });
      return RSVP.all_wait(log_promises).then(function() {
        return persistence.store('settings', {logs: []}, 'bigLogs');
      }, function(err) {
        return persistence.store('settings', {logs: fails}, 'bigLogs');
      });
    }, function(err) {
      return RSVP.resolve([]);
    });
  },
  sync_buttons: function(synced_boards) {
    return RSVP.resolve();
//     return new RSVP.Promise(function(buttons_resolve, buttons_reject) {
//       var buttons_in_sequence = [];
//       synced_boards.forEach(function(board) {
//         var images = board.get('local_images_with_license');
//         // TODO: add them in "proper" order, whatever that means
//         board.get('buttons').forEach(function(button) {
//           button.board_id = board.get('id');
//           if(button.load_board) {
//             button.load_board_id = button.load_board.id;
//           }
//           var image = images.find(function(i) { return i.get('id') == button.image_id; });
//           if(image) {
//             button.image = image.get('url');
//           }
//           // TODO: include the image here, if it makes things easier. Sync
//           // can be a more expensive process than find_button should be..
//           buttons_in_sequence.push(button);
//         });
//       });
//       persistence.store('settings', {list: buttons_in_sequence}, 'syncedButtons').then(function(res) {
//         buttons_resolve();
//       }, function() {
//         buttons_reject();
//       });
//     });
  },
  sync_supervisees: function(user, force) {
    return new RSVP.Promise(function(resolve, reject) {
      var supervisee_promises = [];
      user.get('supervisees').forEach(function(supervisee) {
        var find_supervisee = persistence.queue_sync_action('find_supervisee', function() {
          return CoughDrop.store.findRecord('user', supervisee.id);
        });
        var reload_supervisee = find_supervisee.then(function(record) {
          if(!record.get('fresh') || force) {
            return record.reload();
          } else {
            return record;
          }
        });

        var sync_supervisee = reload_supervisee.then(function(supervisee_user) {
          if(supervisee_user.get('permissions.supervise')) {
            console.log('syncing supervisee: ' + supervisee.user_name + " " + supervisee.id);
            return persistence.sync(supervisee.id, force, true);
          } else {
            return RSVP.reject({error: "supervise permission missing"});
          }
        });
        var complete = sync_supervisee.then(null, function(err) {
          console.log(err);
          console.error("supervisee sync failed");
          modal.warning(i18n.t('supervisee_sync_failed', "Couldn't sync boards for supervisee \"" + supervisee.user_name + "\""));
          return RSVP.resolve({});
        });
        supervisee_promises.push(complete);
      });
      RSVP.all_wait(supervisee_promises).then(function() {
        resolve(user.get('supervisees'));
      }, function() {
        reject.apply(null, arguments);
      });
    });
  },
  board_lookup: function(id, safely_cached_boards, fresh_board_revisions) {
    if(!persistence.get('sync_progress') || persistence.get('sync_progress.canceled')) {
      return RSVP.reject({error: 'canceled'});
    }
    var lookups = persistence.get('sync_progress.key_lookups');
    var board_statuses = persistence.get('sync_progress.board_statuses');
    if(!lookups) {
      lookups = {};
      if(persistence.get('sync_progress')) {
        persistence.set('sync_progress.key_lookups', lookups);
      }
    }
    if(!board_statuses) {
      board_statuses = [];
      if(persistence.get('sync_progress')) {
        persistence.set('sync_progress.board_statuses', board_statuses);
      }
    }
    var lookup_id = id;
    if(lookups[id] && !lookups[id].then) { lookup_id = lookups[id].get('id'); }

    var peeked = CoughDrop.store.peekRecord('board', lookup_id);
    var key_for_id = lookup_id.match(/\//);
    var partial_load = peeked && (!peeked.get('permissions') || !peeked.get('image_urls'));
    if(peeked && (!peeked.get('permissions') || !peeked.get('image_urls'))) { peeked = null; }
    var find_board = null;
    // because of async, it's possible that two threads will try
    // to look up the same board independently, especially with supervisees
    if(lookups[id] && lookups[id].then) {
      find_board = lookups[id];
    } else {
      find_board = CoughDrop.store.findRecord('board', lookup_id);
      find_board = find_board.then(function(record) {
        var cache_mismatch = fresh_board_revisions && fresh_board_revisions[id] && fresh_board_revisions[id] != record.get('current_revision');
        var fresh = record.get('fresh') && !cache_mismatch;
        if(!fresh || key_for_id || partial_load) {
          local_full_set_revision = record.get('full_set_revision');
          // If the board is in the list of already-up-to-date, don't call reload
          if(record.get('permissions') && record.get('image_urls') && safely_cached_boards[id] && !cache_mismatch) {
            board_statuses.push({id: id, key: record.get('key'), status: 'cached'});
            return record;
          } else if(record.get('permissions') && fresh_board_revisions && fresh_board_revisions[id] && fresh_board_revisions[id] == record.get('current_revision')) {
            board_statuses.push({id: id, key: record.get('key'), status: 'cached'});
            return record;
          } else {
            board_statuses.push({id: id, key: record.get('key'), status: 're-downloaded'});
            return record.reload();
          }
        } else {
          board_statuses.push({id: id, key: record.get('key'), status: 'downloaded'});
          return record;
        }
      });
      if(!lookups[id]) {
        lookups[id] = find_board;
      }
    }

    var local_full_set_revision = null;

    return find_board.then(function(board) {
      lookups[id] = RSVP.resolve(board);
      board.set('local_full_set_revision', local_full_set_revision);
      return board;
    });
  },
  queue_sync_action: function(action, method) {
    if(!persistence.get('sync_progress') || persistence.get('sync_progress.canceled')) {
      return RSVP.reject({error: 'canceled'});
    }
    var defer = RSVP.defer();
    defer.callback = method;
    defer.descriptor = action;
    defer.id = (new Date()).getTime() + '-' + Math.random();
    persistence.sync_actions = persistence.sync_actions || [];
    if(capabilities.log_events) {
      console.warn("queueing sync action", defer.descriptor, defer.id);
    }
    persistence.sync_actions.push(defer);
    var threads = capabilities.mobile ? 1 : 4;

    persistence.syncing_action_watchers = persistence.syncing_action_watchers || 0;
    if(persistence.syncing_action_watchers < threads) {
      persistence.syncing_action_watchers++;
      persistence.next_sync_action();
    }
    return defer.promise;
  },
  next_sync_action: function() {
    persistence.sync_actions = persistence.sync_actions || [];
    var action = persistence.sync_actions.shift();
    var next = function() {
      runLater(function() { persistence.next_sync_action(); });
    };
    if(action && action.callback) {
      var start = (new Date()).getTime();
      if(capabilities.log_events) {
        console.warn("executing sync action", action.descriptor, action.id);
      }
      try {
        action.callback().then(function(r) {
          if(capabilities.log_events) {
            var end = (new Date()).getTime();
            console.warn(end - start, "done executing sync action", action.descriptor, action.id);
          }
          action.resolve(r);
          next();
        }, function(e) {
          action.reject(e);
          next();
        });
      } catch(e) {
        action.reject(e);
        next();
      }
    } else {
      if(persistence.syncing_action_watchers) {
        persistence.syncing_action_watchers--;
      }
    }
  },
  sync_boards: function(user, importantIds, synced_boards, force) {
    var full_set_revisions = {};
    var fresh_revisions = {};
    var board_errors = [];
    if(persistence.get('sync_progress.full_set_revisions')) {
      full_set_revisions = persistence.get('sync_progress.full_set_revisions');
    }

    var get_remote_revisions = RSVP.resolve({});
    if(user) {
      get_remote_revisions = persistence.ajax('/api/v1/users/' + user.get('id') + '/board_revisions', {type: 'GET'}).then(function(res) {
        fresh_revisions = res;
        return res;
      }, function() {
        return RSVP.resolve({});
      });
    }

    var all_image_urls = {};
    var get_images = get_remote_revisions.then(function() {
      return persistence.queue_sync_action('find_all_image_urls', function() {
        return coughDropExtras.storage.find_all('image').then(function(list) {
          list.forEach(function(img) {
            if(img.data && img.data.id && img.data.raw && img.data.raw.url) {
              all_image_urls[img.data.id] = img.data.raw.url;
            }
          });
        });
      });
    });

    var all_sound_urls = {};
    var get_sounds = get_images.then(function() {
      return persistence.queue_sync_action('find_all_sound_urls', function() {
        return coughDropExtras.storage.find_all('sound').then(function(list) {
          list.forEach(function(snd) {
            if(snd.data && snd.data.id && snd.data.raw && snd.data.raw.url) {
              all_sound_urls[snd.data.id] = snd.data.raw.url;
            }
          });
        });
      });
    });

    var sync_all_boards = get_sounds.then(function() {
      return new RSVP.Promise(function(resolve, reject) {
        var to_visit_boards = [];
        if(user.get('preferences.home_board.id')) {
          var board = user.get('preferences.home_board');
          board.depth = 0;
          board.visit_source = "home board";
          to_visit_boards.push(board);
        }
        if(user.get('preferences.sidebar_boards')) {
          user.get('preferences.sidebar_boards').forEach(function(b) {
            if(b.key) {
              to_visit_boards.push({key: b.key, depth: 1, image: b.image, visit_source: "sidebar board"});
            }
          });
        }
        var safely_cached_boards = {};
        var checked_linked_boards = {};

        var visited_boards = [];
        if(!persistence.get('sync_progress.progress_for')) {
          persistence.set('sync_progress.progress_for', {});
          persistence.get('sync_progress.progress_for')[user.get('id')] = {
            visited: visited_boards.length,
            to_visit: to_visit_boards.length,
            board_errors: board_errors
          };
          persistence.update_sync_progress();
        }
        var board_load_promises = [];
        var dead_thread = false;
        function nextBoard(defer) {
          if(dead_thread) { defer.reject({error: "someone else failed"}); return; }
          if(!persistence.get('sync_progress') || persistence.get('sync_progress.canceled')) {
            defer.reject({error: 'canceled'});
            return;
          }
          var p_for = persistence.get('sync_progress.progress_for');
          if(p_for) {
            p_for[user.get('id')] = {
              visited: visited_boards.length,
              to_visit: to_visit_boards.length,
              board_errors: board_errors
            };
          }
          persistence.update_sync_progress();
          var next = to_visit_boards.shift();
          var id = next && (next.id || next.key);
          var key = next && next.key;
          var source = next && next.visit_source;
          if(next && next.depth < 20 && id && !visited_boards.find(function(i) { return i == id; })) {
            var local_full_set_revision = null;

            // check if there's a local copy that's already been loaded
            var find_board = persistence.board_lookup(id, safely_cached_boards, fresh_revisions);

            find_board.then(function(board) {
              local_full_set_revision = board.get('local_full_set_revision');
              importantIds.push('board_' + id);
              board.load_button_set();
              var visited_board_promises = [];
              var safely_cached = !!safely_cached_boards[board.id];
              // If the retrieved board's revision matches the synced cache's revision,
              // then this board and all its children should be already in the db.
              var cache_mismatch = fresh_revisions && fresh_revisions[board.get('id')] && fresh_revisions[board.get('id')] != board.get('current_revision');
              // If the synced revision code matches the current copy, and there's nothing fresher that's been downloaded since, then it should be safely cached
              safely_cached = safely_cached || (full_set_revisions[board.get('id')] && board.get('full_set_revision') == full_set_revisions[board.get('id')] && !cache_mismatch);
              // If the board has been loaded locally but not via sync, then this check will return true even though the content hasn't
              // been saved for offline use. That would be wrong, and mildly offensive.
//               safely_cached = safely_cached || (fresh_revisions[board.get('id')] && board.get('current_revision') == fresh_revisions[board.get('id')]);
              if(force == 'all_reload') { safely_cached = false; }
              if(safely_cached) {
                console.log("this board (" + board.get('key') + ") has already been cached locally");
              }
              synced_boards.push(board);
              visited_boards.push(id);

              if(board.get('icon_url_with_fallback').match(/^http/)) {
                  // store_url already has a queue, we don't need to fill the sync queue with these
                visited_board_promises.push(//persistence.queue_sync_action('store_icon', function() {
                    /*return*/ persistence.store_url(board.get('icon_url_with_fallback'), 'image', false, force, true).then(null, function() {
                    console.log("icon url failed to sync, " + board.get('icon_url_with_fallback'));
                    return RSVP.resolve();
                  })
               /*})*/);
                importantIds.push("dataCache_" + board.get('icon_url_with_fallback'));
              }

              if(next.image) {
                visited_board_promises.push(//persistence.queue_sync_action('store_sidebar_image', function() {
                  /*return*/ persistence.store_url(next.image, 'image', false, force, true).then(null, function() {
                    return RSVP.reject({error: "sidebar icon url failed to sync, " + next.image});
                  })
               /*})*/);
                importantIds.push("dataCache_" + next.image);
              }

              board.map_image_urls(all_image_urls).forEach(function(image) {
//               board.get('local_images_with_license').forEach(function(image) {
                importantIds.push("image_" + image.id);
                var keep_big = !!(board.get('grid.rows') < 3 || board.get('grid.columns') < 6);
                if(image.url && image.url.match(/^http/)) {
                  // TODO: should this be app_state.currentUser instead of the currently-syncing user?
                  var personalized = image.url;
                  if(CoughDrop.Image && CoughDrop.Image.personalize_url) {
                    personalized = CoughDrop.Image.personalize_url(image.url, user.get('user_token'));
                  }

                  visited_board_promises.push(//persistence.queue_sync_action('store_button_image', function() {
                    /*return*/ persistence.store_url(personalized, 'image', keep_big, force, true).then(null, function() {
                      return RSVP.reject({error: "button image failed to sync, " + image.url});
                    })
                 /*})*/);
                  importantIds.push("dataCache_" + image.url);
                }
              });
              board.map_sound_urls(all_sound_urls).forEach(function(sound) {
//               board.get('local_sounds_with_license').forEach(function(sound) {
                importantIds.push("sound_" + sound.id);
                if(sound.url && sound.url.match(/^http/)) {
                  visited_board_promises.push(//persistence.queue_sync_action('store_button_sound', function() {
                     /*return*/ persistence.store_url(sound.url, 'sound', false, force, true).then(null, function() {
                      return RSVP.reject({error: "button sound failed to sync, " + sound.url});
                     })
                  /*})*/);
                  importantIds.push("dataCache_" + sound.url);
                }
              });
              var prior_board = board;
              board.get('linked_boards').forEach(function(board) {
                // don't re-visit if we've already grabbed it for this sync
                var already_visited = visited_boards.find(function(i) { return i == board.id || i == board.key; });
                // don't add to the list if already planning to visit (and either
                // the planned visit doesn't have link_disabled flag or the
                // two entries match for the link_disabled flag)
                var already_going_to_visit = to_visit_boards.find(function(b) { return (b.id == board.id || b.key == board.key) && (!board.link_disabled || board.link_disabled == b.link_disabled); });

                // if we've already confirmed the sub-board from a different board, you can
                // skip the check this time
                if(safely_cached_boards[board.id]) {// || checked_linked_boards[board.id]) {
                  return;
                }

                if(!already_visited && !already_going_to_visit) {
                  to_visit_boards.push({id: board.id, key: board.key, depth: next.depth + 1, link_disabled: board.link_disabled, visit_source: (emberGet(prior_board, 'key') || emberGet(prior_board, 'id'))});
                }
                var force_cache_check = true;
                if(safely_cached || force_cache_check) {
                  // (this check is here because it's possible to lose some data via leakage,
                  // since if a board is safely cached it's sub-boards should be as well,
                  // but unfortunately sometimes they're not)
                  var find = persistence.queue_sync_action('find_board', function() {
                    return persistence.find('board', board.id);
                  });
                  // for every linked board, check all the board's buttons. If all the images
                  // and sounds are already in the cache then mark the board as safely cached.
                  visited_board_promises.push(
                    find.then(function(b) {
                      var necessary_finds = [];
                      // this is probably a protective thing, but I have no idea why anymore,
                      // it may not even be necessary anymore
                      var tmp_board = CoughDrop.store.createRecord('board', $.extend({}, b, {id: null}));
                      var missing_image_ids = [];
                      var missing_sound_ids = [];
                      var local_image_map = tmp_board.get('image_urls') || {};
                      var local_sound_map = tmp_board.get('sound_urls') || {};
                      tmp_board.get('used_buttons').forEach(function(button) {
                        if(button.image_id) {
                          var valid = false;
                          var mapped_url = all_image_urls[button.image_id] || local_image_map[button.image_id];
                          if(mapped_url) {
                            if((persistence.url_cache && persistence.url_cache[mapped_url]) && (!persistence.url_uncache || !persistence.url_uncache[mapped_url])) {
                              valid = true;
                            }
                          }
                          if(!valid && !button.image_id.match(/^tmp_/)) {
                            missing_image_ids.push(button.image_id);
                          }
                        }
                        if(button.sound_id) {
                          var valid = false;
                          var mapped_url = all_sound_urls[button.sound_id] || local_sound_map[button.sound_id];
                          if(mapped_url) {
                            if((persistence.url_cache && persistence.url_cache[mapped_url]) && (!persistence.url_uncache || !persistence.url_uncache[mapped_url])) {
                              valid = true;
                            }
                          }
                          if(!valid && !button.sound_id.match(/^tmp_/)) {
                            missing_sound_ids.push(button.sound_id);
                          }
                        }
                      });
                      necessary_finds.push(new RSVP.Promise(function(res, rej) {
                        if(missing_image_ids.length > 0) {
                          rej({error: 'missing image ids', ids: missing_image_ids});
                        } else if(missing_sound_ids.length > 0) {
                          rej({error: 'missing sound ids', ids: missing_sound_ids});
                        } else {
                          res();
                        }
                      }));
                      return RSVP.all_wait(necessary_finds).then(function() {
                        var cache_mismatch = fresh_revisions && fresh_revisions[board.id] && fresh_revisions[board.id] != b.current_revision;
                        if(!cache_mismatch) {
                          safely_cached_boards[board.id] = true;
                        }
                        checked_linked_boards[board.id] = true;
                      }, function(error) {
                        if(safely_cached) {
                          console.log(error);
                          console.log("should have been safely cached, but board content wasn't in db:" + board.id);
                        }
                        checked_linked_boards[board.id] = true;
                        return RSVP.resolve();
                      });
                    }, function(error) {
                      if(safely_cached) {
                        console.log(error);
                        console.log("should have been safely cached, but board wasn't in db:" + board.id);
                      }
                      checked_linked_boards[board.id] = true;
                      return RSVP.resolve();
                    })
                  );
                }
              });

              RSVP.all_wait(visited_board_promises).then(function() {
                full_set_revisions[board.get('id')] = board.get('full_set_revision');
                runLater(function() {
                  nextBoard(defer);
                }, 150);
              }, function(err) {
                var msg = "board " + (key || id) + " failed to sync completely";
                if(typeof err == 'string') {
                  msg = msg + ": " + err;
                } else if(err && err.error) {
                  msg = msg + ": " + err.error;
                }
                if(source) {
                   msg = msg + ", linked from " + source;
                }
                board_errors.push({error: msg, board_id: id, board_key: key});
                runLater(function() {
                  nextBoard(defer);
                }, 150);
              });
            }, function(err) {
              var board_unauthorized = (err && err.error == "Not authorized");
              if(next.link_disabled && board_unauthorized) {
                // TODO: if a link is disabled, can we get away with ignoring an unauthorized board?
                // Prolly, since they won't be using that board anyway without an edit.
                runLater(function() {
                  nextBoard(defer);
                }, 150);
              } else {
                board_errors.push({error: "board " + (key || id) + " failed retrieval for syncing, linked from " + source, board_unauthorized: board_unauthorized, board_id: id, board_key: key});
                runLater(function() {
                  nextBoard(defer);
                }, 150);
              }
            });
          } else if(!next) {
            // TODO: mark this defer's promise as waiting (needs to be unmarked at each
            // nextBoard call), then set a longer timeout before calling nextBoard,
            // and only resolve when *all* the promises are waiting.
            defer.resolve();
          } else {
            runLater(function() {
              nextBoard(defer);
            }, 50);
          }
        }
        // threaded lookups, though a polling pool would probably be better since all
        // could resolve and then the final one finds a ton more boards
        var n_threads = capabilities.mobile ? 1 : 2;
        for(var threads = 0; threads < 2; threads++) {
          var defer = RSVP.defer();
          nextBoard(defer);
          board_load_promises.push(defer.promise);
        }
        RSVP.all_wait(board_load_promises).then(function() {
          resolve(full_set_revisions);
        }, function(err) {
          dead_thread = true;
          reject.apply(null, arguments);
        });
      });
    });

    return sync_all_boards.then(function(full_set_revisions) {
      return persistence.store('settings', full_set_revisions, 'synced_full_set_revisions');
    });
  },
  sync_user: function(user, importantIds) {
    return new RSVP.Promise(function(resolve, reject) {
      importantIds.push('user_' + user.get('id'));
      var find_user = user.reload().then(function(u) {
        if(persistence.get('sync_progress.root_user') == u.get('id')) {
          persistence.set('sync_progress.last_sync_stamp', u.get('sync_stamp'));
        }

        return RSVP.resolve(u);
      }, function() {
        reject({error: "failed to retrieve latest user details"});
      });

      // also download the latest avatar as a data uri
      var save_avatar = find_user.then(function(user) {
        // is this also a user object? does user = u work??
        if(persistence.get('sync_progress.root_user') == user.get('id')) {
          if(user.get('preferences.device') && !user.get('preferences.device.ever_synced') && user.save) {
            user.set('preferences.device.ever_synced', true);
            user.save();
          }
        }
        var url = user.get('avatar_url');
        return persistence.store_url(url, 'image');
      });

      save_avatar.then(function(object) {
        importantIds.push("dataCache_" + object.url);
        resolve();
      }, function(err) {
        if(err && err.quota_maxed) {
          reject({error: "failed to save user avatar, storage is full"});
        } else {
          reject({error: "failed to save user avatar"});
        }
      });
    });
  },
  sync_changed: function() {
    return new RSVP.Promise(function(resolve, reject) {
      var changed = persistence.find_changed().then(null, function() {
        reject({error: "failed to retrieve list of changed records"});
      });

      changed.then(function(list) {
        var update_promises = [];
        var tmp_id_map = {};
        var re_updates = [];
        // TODO: need to better handle errors with updates and deletes
        list.forEach(function(item) {
          if(item.store == 'deletion') {
            var promise = persistence.queue_sync_action('find_deletion', function() {
              return CoughDrop.store.findRecord(item.data.store, item.data.id).then(function(res) {
                res.deleteRecord();
                return res.save().then(function() {
                  return persistence.remove(item.store, item.data);
                }, function() { debugger; });
              }, function() {
                // if it's already deleted, there's nothing for us to do
                return RSVP.resolve();
              });
            });
            update_promises.push(promise);
          } else if(item.store == 'board' || item.store == 'image' || item.store == 'sound' || item.store == 'user') {
            var find_record = null;
            var object = item.data.raw[item.store] || item.data.raw;
            var object_id = object.id;
            var tmp_id = null;
            if(object.id && object.id.match(/^tmp_/)) {
              tmp_id = object.id;
              object.id = null;
              find_record = RSVP.resolve(CoughDrop.store.createRecord(item.store, object));
            } else {
              find_record = persistence.queue_sync_action('find_changed_record', function() {
                return CoughDrop.store.findRecord(item.store, object.id).then(null, function() {
                  return RSVP.reject({error: "failed to retrieve " + item.store + " " + object.id + "for updating"});
                });
              });
            }
            var save_item = find_record.then(function(record) {
              // TODO: check for conflicts before saving...
              record.setProperties(object);
              if(!record.get('id') && (item.store == 'image' || item.store == 'sound')) {
                record.set('data_url', object.data_url);
                return contentGrabbers.save_record(record).then(function() {
                  return record.reload();
                });
              } else {
                return record.save();
              }
            });

            var result = save_item.then(function(record) {
              if(item.store == 'board' && JSON.stringify(object).match(/tmp_/)) { // TODO: if item has temporary pointers
                re_updates.push([item, record]);
              }
              if(tmp_id) {
                tmp_id_map[tmp_id] = record;
                return persistence.remove(item.store, {}, tmp_id);
              }
              return RSVP.resolve();
            }, function() {
              return RSVP.reject({error: "failed to save offline record, " + item.store + " " + object_id});
            });

            update_promises.push(result);
          }
        });
        RSVP.all_wait(update_promises).then(function() {
          if(re_updates.length > 0) {
            var re_update_promises = [];
            re_updates.forEach(function(update) {
              var item = update[0];
              var record = update[1];
              if(item.store == 'board') {
                var buttons = record.get('buttons');
                if(buttons) {
                  for(var idx = 0; idx < buttons.length; idx++) {
                    var button = buttons[idx];
                    if(tmp_id_map[button.image_id]) {
                      button.image_id = tmp_id_map[button.image_id].get('id');
                    }
                    if(tmp_id_map[button.sound_id]) {
                      button.sound_id = tmp_id_map[button.sound_id].get('id');
                    }
                    if(button.load_board && tmp_id_map[button.load_board.id]) {
                      var board = tmp_id_map[button.load_board.id];
                      button.load_board = {
                        id: board.get('id'),
                        key: board.get('key')
                      };
                    }
                    buttons[idx] = button;
                  }
                }
                record.set('buttons', buttons);
              } else {
                debugger;
              }
              // TODO: update any tmp_ids from item in record using tmp_id_map
              re_update_promises.push(record.save());
            });
            RSVP.all_wait(re_update_promises).then(function() {
              resolve();
            }, function(err) {
              reject(err);
            });
          } else {
            resolve();
          }
        }, function(err) {
          reject(err);
        });
      });
    });
  },
  temporary_id: function() {
    return "tmp_" + Math.random().toString() + (new Date()).getTime().toString();
  },
  convert_model_to_json: function(store, modelName, record) {
    var type = store.modelFor(modelName);
    var data = {};
    var serializer = store.serializerFor(type.modelName);

    var snapshot = record; //._createSnapshot();
    serializer.serializeIntoHash(data, type, snapshot, { includeId: true });

    // TODO: mimic any server-side changes that need to happen to make the record usable
    if(!data[type.modelName].id) {
      data[type.modelName].id = persistence.temporary_id();
    }
    if(type.mimic_server_processing) {
      data = type.mimic_server_processing(snapshot.record, data);
    }

    return data;
  },
  offline_reject: function() {
    return RSVP.reject({offline: true, error: "not online"});
  },
  meta: function(store, obj) {
    if(obj && obj.get('meta')) {
      return obj.get('meta');
    } else if(obj && obj.get('id')) {
      var res = coughDropExtras.meta('GET', store, obj.get('id'));
      res = res || coughDropExtras.meta('PUT', store, obj.get('id'));
      res = res || coughDropExtras.meta('GET', store, obj.get('user_name') || obj.get('key'));
      return res;
    } else if(!obj) {
      return coughDropExtras.meta('POST', store, null);
    }
    return null;
  },
  ajax: function() {
    if(this.get('online')) {
      var ajax_args = arguments;
      // TODO: is this wrapper necessary? what's it for? maybe can just listen on
      // global ajax for errors instead...
      return new RSVP.Promise(function(resolve, reject) {
        $.ajax.apply(null, ajax_args).then(function(data, message, xhr) {
          run(function() {
            if(data) {
              data.xhr = xhr;
            }
            resolve(data);
          });
        }, function(xhr) {
          // TODO: for some reason, safari returns the promise instead of the promise's
          // result to this handler. I'm sure it's something I'm doing wrong, but I haven't
          // been able to figure it out yet. This is a band-aid.
          if(xhr.then) { console.log("received the promise instead of the promise's result.."); }
          var promise = xhr.then ? xhr : RSVP.reject(xhr);
          promise.then(null, function(xhr) {
            var allow_offline_error = false;
            if(allow_offline_error) { // TODO: check for offline error in xhr
              reject(xhr, {offline: true, error: "not online"});
            } else {
              reject(xhr);
            }
          });
        });
      });
    } else {
      return RSVP.reject(null, {offline: true, error: "not online"});
    }
  },
  on_connect: function() {
    stashes.set('online', this.get('online'));
    if(this.get('online') && (!CoughDrop.testing || CoughDrop.sync_testing)) {
      var _this = this;
      runLater(function() {
        // TODO: maybe do a quick xhr to a static asset to make sure we're for reals online?
        if(stashes.get('auth_settings')) {
          _this.check_for_needs_sync(true);
        }
        _this.tokens = {};
        if(CoughDrop.session) {
          CoughDrop.session.restore(!persistence.get('browserToken'));
        }
      }, 500);
    }
  }.observes('online'),
  check_for_needs_sync: function(ref) {
    var force = (ref === true);
    var _this = this;

    if(stashes.get('auth_settings') && window.coughDropExtras && window.coughDropExtras.ready) {
      var synced = _this.get('last_sync_at') || 0;
      var syncable = persistence.get('online') && !Ember.testing && !persistence.get('syncing');
      var interval = persistence.get('last_sync_stamp_interval') || (5 * 60 * 1000);
      interval = interval + (0.2 * interval * Math.random()); // jitter
      if(_this.get('last_sync_event_at')) {
        // don't background sync too often
        syncable = syncable && (_this.get('last_sync_event_at') < ((new Date()).getTime() - interval));
      }
      var now = (new Date()).getTime() / 1000;
      if(!Ember.testing && capabilities.mobile && !force && loaded && (now - loaded) < (30) && synced > 1) {
        // on mobile, don't auto-sync until 30 seconds after bootup, unless it's never been synced
        // NOTE: the db is keyed to the user, so you'll always have a user-specific last_sync_at
        return false;
      } else if(persistence.get('auto_sync') === false || persistence.get('auto_sync') == null) {
        // on browsers, don't auto-sync until the user has manually synced at least once
        return false;
      } else if(synced > 0 && (now - synced) > (48 * 60 * 60) && syncable) {
        // if we haven't synced in 48 hours and we're online, do a background sync
        console.debug('syncing because it has been more than 48 hours');
        persistence.sync('self').then(null, function() { });
        return true;
      } else if(force || (syncable && _this.get('last_sync_stamp'))) {
        // don't check sync_stamp more than once every interval
        var last_check = persistence.get('last_sync_stamp_check');
        if(force || !last_check || (last_check < (new Date()).getTime() - interval)) {
          persistence.set('last_sync_stamp_check', (new Date()).getTime());
          persistence.ajax('/api/v1/users/self/sync_stamp', {type: 'GET'}).then(function(res) {
            persistence.set('last_sync_stamp_check', (new Date()).getTime());
            if(!_this.get('last_sync_stamp') || res.sync_stamp != _this.get('last_sync_stamp')) {
              console.debug('syncing because sync_stamp has changed');
              persistence.sync('self').then(null, function() { });
            }
          }, function(err) {
            persistence.set('last_sync_stamp_check', (new Date()).getTime());
            // TODO: if error implies no connection, consider marking as offline and checking for stamp more frequently
            if(err && err.result && err.result.invalid_token) {
              if(stashes.get('auth_settings') && !Ember.testing) {
                if(CoughDrop.session && !CoughDrop.session.get('invalid_token')) {
                  CoughDrop.session.check_token(false);
                }
              }
            }
          });
          return true;
        }
      }
    }
    return false;
  }.observes('refresh_stamp', 'last_sync_at'),
  check_for_sync_reminder: function() {
    var _this = this;
    if(stashes.get('auth_settings') && window.coughDropExtras && window.coughDropExtras.ready) {
      var synced = _this.get('last_sync_at') || 0;
      var now = (new Date()).getTime() / 1000;
      // if we haven't synced in 14 days, remind to sync
      if(synced > 0 && (now - synced) > (14 * 24 * 60 * 60) && !Ember.testing) {
        persistence.set('sync_reminder', true);
      } else {
        persistence.set('sync_reminder', false);
      }
    } else {
      persistence.set('sync_reminder', false);
    }
  }.observes('refresh_stamp', 'last_sync_at'),
  check_for_new_version: function() {
    if(window.CoughDrop.update_version) {
      persistence.set('app_needs_update', true);
    }
  }.observes('refresh_stamp')
}).create({online: (navigator.onLine)});
stashes.set('online', navigator.onLine);

window.addEventListener('online', function() {
  persistence.set('online', true);
});
window.addEventListener('offline', function() {
  persistence.set('online', false);
});
// Cordova notifies on the document object
document.addEventListener('online', function() {
  persistence.set('online', true);
});
document.addEventListener('offline', function() {
  persistence.set('online', false);
});
setInterval(function() {
  if(navigator.onLine === true && persistence.get('online') === false) {
    persistence.set('online', true);
  } else if(navigator.onLine === false && persistence.get('online') === true) {
    persistence.set('online', false);
  } else if(persistence.get('online') === false) {
    // making an AJAX call when offline should have very little overhead
    CoughDrop.session.check_token(false).then(function() {
      persistence.set('online', true);
    }, function() { });
  }
}, 30000);

persistence.DSExtend = {
  grabRecord: function(type, id, opts) {
    // 1. Try to peek for the record
    //    - If peeked but no permissions defined, ignore it
    //    - Otherwise return peeked result
    // 2. Next try local persistence lookup
    //    - If found, push the record and return it
    // 3. Last try calling findRecord as before
    // opts:
    //    - any: allow peeked result even if incomplete
    //    - local: fail instead of trying remote call
    //    - remote: do a .reload unless it's a remote result
  },
  findRecord: function(store, type, id) {
    var _this = this;
    var _super = this._super;

    // first, try looking up the record locally
    var original_find = persistence.find(type.modelName, id, true);
    var find = original_find;

    var full_id = type.modelName + "_" + id;
    // force_reload should always hit the server, though it can return local data if there's a token error (i.e. session expired)
    if(persistence.force_reload == full_id) { find.then(null, function() { }); find = RSVP.reject(); }
    // private browsing mode gets really messed up when you try to query local db, so just don't.
    else if(!stashes.get('enabled')) { find.then(null, function() { }); find = RSVP.reject(); original_find = RSVP.reject(); }

    // this method will be called if a local result is found, or a force reload
    // is called but there wasn't a result available from the remote system
    var local_processed = function(data) {
      data.meta = data.meta || {};
      data.meta.local_result = true;
      if(data[type.modelName] && data.meta && data.meta.local_result) {
        data[type.modelName].local_result = true;
      }
      coughDropExtras.meta_push({
        method: 'GET',
        model: type.modelName,
        id: id,
        meta: data.meta
      });
      return RSVP.resolve(data);
    };


    return find.then(local_processed, function() {
      // if nothing found locally and system is online (and it's not a local-only id), make a remote request
      if(persistence.get('online') && !id.match(/^tmp[_\/]/)) {
        persistence.remember_access('find', type.modelName, id);
        return _super.call(_this, store, type, id).then(function(record) {
          // mark the retrieved timestamp for freshness checks
          if(record[type.modelName]) {
            delete record[type.modelName].local_result;
            var now = (new Date()).getTime();
            record[type.modelName].retrieved = now;
            if(record.images) {
              record.images.forEach(function(i) { i.retrieved = now; });
            }
            if(record.sounds) {
              record.sounds.forEach(function(i) { i.retrieved = now; });
            }
          }
          var ref_id = null;
          if(type.modelName == 'user' && id == 'self') {
            ref_id = 'self';
          }
          // store the result locally for future offline access
          return persistence.store_eventually(type.modelName, record, ref_id).then(function() {
            return RSVP.resolve(record);
          }, function() {
            return RSVP.reject({error: "failed to delayed-persist to local db"});
          });
        }, function(err) {
          var local_fallback = false;
          if(err && (err.invalid_token || (err.result && err.result.invalid_token))) {
            // for expired tokens, allow local results as a fallback
            local_fallback = true;
          } else if(err && err.errors && err.errors[0] && err.errors[0].status && err.errors[0].status.substring(0, 1) == '5') {
            // for server errors, allow local results as a fallback
            local_fallback = true;
          } else if(err && err.fakeXHR && err.fakeXHR.status === 0) {
            // for connection errors, allow local results as a fallback
            local_fallback = true;
          } else if(err && err.fakeXHR && err.fakeXHR.status && err.fakeXHR.status.toString().substring(0, 1) == '5') {
            // for other 500 errors, allow local results as a fallback
            local_fallback = true;
          } else {
            // any other exceptions?
          }
          if(local_fallback) {
            return original_find.then(local_processed, function() { return RSVP.reject(err); });
          } else {
            return RSVP.reject(err);
          }
        });
      } else {
        return original_find.then(local_processed, persistence.offline_reject);
      }
    });
  },
  createRecord: function(store, type, obj) {
    var _this = this;
    if(persistence.get('online')) {
      var tmp_id = null, tmp_key = null;
//       if(obj.id && obj.id.match(/^tmp[_\/]/)) {
//         tmp_id = obj.id;
//         tmp_key = obj.attr('key');
//         var record = obj.record;
//         record.set('id', null);
//         obj = record._createSnapshot();
//       }
      return this._super(store, type, obj).then(function(record) {
        if(obj.record && obj.record.tmp_key) {
          record[type.modelName].tmp_key = obj.record.tmp_key;
        }
        return persistence.store(type.modelName, record).then(function() {
          if(tmp_id) {
            return persistence.remove('board', {}, tmp_id).then(function() {
              return RSVP.resolve(record);
            }, function() {
              return RSVP.reject({error: "failed to remove temporary record"});
            });
          } else {
            return RSVP.resolve(record);
          }
        }, function() {
          return RSVP.reject({error: "failed to create in local db"});
        });
      });
    } else {
      var record = persistence.convert_model_to_json(store, type.modelName, obj);
      record[type.modelName].changed = true;
      if(record[type.modelName].key && record[type.modelName].key.match(/^tmp_/)) {
        record[type.modelName].tmp_key = record[type.modelName].key;
      }
      if(record[type.modelName].id.match(/^tmp/) && ['board', 'image', 'sound'].indexOf(type.modelName) == -1) {
        // only certain record types can be created offline
        return persistence.offline_reject();
      }
      return persistence.store(type.modelName, record).then(function() {
        return RSVP.resolve(record);
      }, function() {
        return persistence.offline_reject();
      });
    }
  },
  updateRecord: function(store, type, obj) {
    if(persistence.get('online')) {
      if(obj.id.match(/^tmp[_\/]/)) {
        return this.createRecord(store, type, obj);
      } else {
        return this._super(store, type, obj).then(function(record) {
          return persistence.store(type.modelName, record).then(function() {
            return RSVP.resolve(record);
          }, function() {
            return RSVP.reject({error: "failed to update to local db"});
          });
        });
      }
    } else {
      var record = persistence.convert_model_to_json(store, type.modelName, obj);
      record[type.modelName].changed = true;
      return persistence.store(type.modelName, record).then(function() {
        RSVP.resolve(record);
      }, function() {
        return persistence.offline_reject();
      });
    }
  },
  deleteRecord: function(store, type, obj) {
    // need raw object
    if(persistence.get('online')) {
      return this._super(store, type, obj).then(function(record) {
        return persistence.remove(type.modelName, record).then(function() {
          return RSVP.resolve(record);
        }, function() {
          return RSVP.reject({error: "failed to delete in local db"});
        });
      });
    } else {
      var record = persistence.convert_model_to_json(store, type.modelName, obj);
      return persistence.remove(type.modelName, record, null, true).then(function() {
        return RSVP.resolve(record);
      });
    }
  },
  findAll: function(store, type, id) {
    debugger;
  },
  query: function(store, type, query) {
    if(persistence.get('online')) {
      var res = this._super(store, type, query);
      return res;
    } else {
      return persistence.offline_reject();
    }
  }
};
window.persistence = persistence;

export default persistence;
