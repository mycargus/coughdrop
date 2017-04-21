import Ember from 'ember';
import modal from '../utils/modal';
import persistence from '../utils/persistence';
import app_state from '../utils/app_state';
import editManager from '../utils/edit_manager';
import i18n from '../utils/i18n';
import Utils from '../utils/misc';

export default modal.ModalController.extend({
  opening: function() {
    this.set('list_type', null);
    this.set('list_type', 'core');
    this.set('core_promise', null);
    this.set('user', this.get('model.user') || app_state.get('currentUser'));
    this.set('category', null);
    this.check_availability();
    this.update_list();
  },
  check_availability: function() {
    var rows = editManager.controller.get('ordered_buttons');
    var empty = 0;
    rows.forEach(function(row) {
      row.forEach(function(col) {
        if(col.empty) { empty++; }
      });
    });
    this.set('full', empty === 0);
    this.set('empty', empty);
  },
  set_list: function(val, type) {
    if(this.get('list_type') == type) {
      this.set('list', val);
    }
  },
  on_board: function(opts) {
    var found = false;
    editManager.controller.ordered_buttons.forEach(function(row) {
      row.forEach(function(button) {
        if(opts.label && button.label && button.label.toLowerCase() == opts.label.toLowerCase()) {
          found = true;
        } else if(opts.sound_id && button.sound_id == opts.sound_id) {
          found = true;
        }
      });
    });
    if(!found && opts.label) {
      var buttons = this.get('model.board.button_set.buttons');
      if(buttons) {
        buttons.forEach(function(btn) {
          if(btn.label && btn.label.toLowerCase() == opts.label.toLowerCase()) {
            found = true;
          }
        });
      }
    }
    return found;
  },
  update_list: function() {
    var type = this.get('list_type');
    this.set('core', false);
    this.set('fringe', false);
    this.set('recordings', false);
    this.set('requests', false);
    if(!this.get('user.id') || !this.get('list_type')) { return; }
    this.set(type, true);
    var _this = this;
    if(type == 'core' || type == 'fringe' || type == 'requests') {
      this.set_list({loading: true}, type);
      if(_this.get('core_promise.user_id') != _this.get('user.id')) { _this.set('core_promise', null); }
      if(!_this.get('core_promise')) { _this.set('core_promise', persistence.ajax('/api/v1/users/' + this.get('user.id') + '/core_lists', {type: 'GET'})); }
      _this.set('core_promise.user_id', _this.get('user.id'));
      _this.get('core_promise').then(function(res) {
        _this.set('core_list', list);
        if(type == 'core') {
          var items = res.for_user.map(function(str) {
            var item = {text: str};
            if(res.reachable_for_user.indexOf(str.toLowerCase()) >= 0) { item.used = true; }
            else if(_this.on_board({label: str})) { item.used = true; }
            return item;
          });
          var list = { items: items };
          _this.set_list(list, type);
          _this.set('category', list);
        } else if(type == 'requests') {
          var items = (res.requested_phrases_for_user || []).map(function(phrase) {
            var item = {text: phrase.text, used: phrase.used};
            if(_this.on_board({label: phrase.text})) { item.used = true; }
            return item;
          });
          var list = { items: items };
          _this.set_list(list, type);
          _this.set('category', list);
        } else {
          var list = res.fringe[0];
          list.categories.forEach(function(cat, idx) {
            items = [];
            cat.words.forEach(function(str) {
              var item = {text: str};
              if(res.reachable_fringe_for_user.indexOf(str.toLowerCase()) >= 0) { item.used = true; }
              else if(_this.on_board({label: str})) { item.used = true; }
              items.push(item);
            });
            list.categories[idx].items = items;
          });
          _this.set_list(list, type);
        }
      }, function(err) {
        _this.set_list({error: true}, type);
        _this.set('core_promise', null);
      });
    } else if(type == 'recordings') {
      // load the user's home button sets
      _this.set_list({loading: true}, 'recordings');
      Utils.all_pages('buttonset', {user_id: _this.get('user.id')}, function() { }).then(function(sets) {
        var sound_ids = {};
        sets.forEach(function(button_set) {
          button_set.get('buttons').forEach(function(button) {
            if(button.sound_id) {
              sound_ids[button.sound_id] = true;
            }
          });
        });
        Utils.all_pages('sound', {user_id: _this.get('user.id')}, function(res) { }).then(function(sounds) {
          var sounds_hash = {};
          sounds.forEach(function(s) {
            (s.get('tags') || []).forEach(function(tag) {
              sounds_hash[tag] = s;
            });
          });

          persistence.ajax('/api/v1/users/' + _this.get('user.id') + '/message_bank_suggestions', {type: 'GET'}).then(function(lists) {
            var items = [];
            var list = lists[0];
            var res = {id: 'all_recordings', name: "Recordings", categories: []};
            var used_sounds = {};
            list.categories.forEach(function(category) {
              var items = [];
              category.phrases.forEach(function(phrase) {
                var tag = list.id + ":" + category.id + ":" + phrase.id;
                if(sounds_hash[tag]) {
                  used_sounds[sounds_hash[tag].get('id')] = true;
                  var item = {text: phrase.text};
                  if(sound_ids[sounds_hash[tag].get('id')]) { item.used = true; }
                  else if(_this.on_board({sound_id: sounds_hash[tag].get('id')})) { item.used = true; }
                  items.push(item);
                }
              });
              if(items.length > 0) {
                res.categories.push({
                  name: category.name,
                  id: category.id,
                  items: items
                });
              }
            });
            var extras = [];
            sounds.forEach(function(sound) {
              if(!used_sounds[sound.get('id')]) {
                var item = { text: sound.get('transcription') || sound.get('name'), sound: sound };
                if(sound_ids[sound.get('id')]) { item.used = true; }
                else if(_this.on_board({sound_id: sound.get('id')})) { item.used = true; }
                extras.push(item);
              }
            });
            if(extras.length > 0) {
              res.categories.unshift({
                name: "Other Recordings",
                id: 'other_recordings',
                items: extras
              });
            }
            _this.set_list(res, 'recordings');
          }, function(err) {
            _this.set_list({error: true}, 'recordings');
          });
        }, function(err) {
          _this.set_list({error: true}, 'recordings');
        });
      }, function(err) {
        _this.set_list({error: true}, 'recordings');
      });
    }
  }.observes('list_type', 'user'),
  actions: {
    select_list: function(list) {
      this.set('category', null);
      this.set('list_type', list);
    },
    select_category: function(category) {
      this.set('category', category);
    },
    add_item: function(item) {
      if(this.get('full')) { return; }
      var board = this.get('model.board');
      var button = editManager.find_button('empty');
      if(button) {
        editManager.change_button(button.id, {
          label: item.text,
          sound: item.sound,
          sound_id: (item.sound && item.sound.get('id'))
        });
        editManager.lucky_symbol(button.id);
      }
      Ember.set(item, 'used', true);
      this.check_availability();
    }
  }
});
