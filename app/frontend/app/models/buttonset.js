import Ember from 'ember';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import $ from 'jquery';
import RSVP from 'rsvp';
import DS from 'ember-data';
import CoughDrop from '../app';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';
import app_state from '../utils/app_state';
import stashes from '../utils/_stashes';
import word_suggestions from '../utils/word_suggestions';
import Utils from '../utils/misc';

CoughDrop.Buttonset = DS.Model.extend({
  key: DS.attr('string'),
  buttons_json: DS.attr('raw'),
  buttons: DS.attr('raw'),
  board_ids: DS.attr('raw'),
  name: DS.attr('string'),
  full_set_revision: DS.attr('string'),
  set_buttons: function() {
    var buttons = null;
    try {
      buttons = JSON.parse(this.get('buttons_json'));
    } catch(e) { }
    this.set('buttons', buttons);
  }.observes('buttons_json'),
  find_buttons: function(str, from_board_id, user, include_home_and_sidebar) {
    if(str.length === 0) { return RSVP.resolve([]); }
    var buttons = this.get('buttons') || [];
    var images = CoughDrop.store.peekAll('image');

    var matching_buttons = [];
    var re = new RegExp("\\b" + str, 'i');
    var all_buttons_enabled = stashes.get('all_buttons_enabled');

    if(from_board_id && from_board_id != this.get('id')) {
      // re-depthify all the buttons based on the starting board
      var new_buttons = [];
      var boards_to_check = [{id: from_board_id, depth: 0}];
      var found_boards = [];
      var check_button = function(b) {
        if(b.board_id == board_to_check.id) {
          var new_b = $.extend({}, b, {depth: board_to_check.depth});
          new_buttons.push(new_b);
          if(b.linked_board_id && found_boards.indexOf(b.linked_board_id) == -1) {
            found_boards.push(b.linked_board_id);
            boards_to_check.push({id: b.linked_board_id, depth: board_to_check.depth + 1});
          }
        }
      };
      while(boards_to_check.length > 0) {
        var board_to_check = boards_to_check.shift();
        buttons.forEach(check_button);
        // make sure to keep the list breadth-first!
        boards_to_check.sort(function(a, b) { return b.depth - a.depth; });
      }
      buttons = new_buttons;
    }

    buttons.forEach(function(button, idx) {
      // TODO: optionally show buttons on link-disabled boards
      if(!button.hidden || all_buttons_enabled) {
        var match_level = (button.label && button.label.match(re) && 3);
        match_level = match_level || (button.vocalization && button.vocalization.match(re) && 2);
        match_level = match_level || (button.label && word_suggestions.edit_distance(str, button.label) < Math.max(str.length, button.label.length) * 0.5 && 1);
        if(match_level) {
          button = $.extend({}, button);
          if(button.image) {
            button.image = CoughDrop.Image.personalize_url(button.image, app_state.get('currentUser.user_token'));
          }
          var image = images.findBy('id', button.image_id);
          if(image) {
            button.image = image.get('best_url');
          }
          emberSet(button, 'image', emberGet(button, 'image') || Ember.templateHelpers.path('blank.png'));
          emberSet(button, 'on_this_board', (emberGet(button, 'depth') === 0));
          var path = [];
          var depth = button.depth || 0;
          var ref_button = button;
          var allow_unpreferred = false;
          var button_to_get_here = null;
          var check_for_match = function(parent_button) {
            if(!button_to_get_here && !parent_button.link_disabled && (!parent_button.hidden || all_buttons_enabled)) {
              if(parent_button.linked_board_id == ref_button.board_id && (allow_unpreferred || parent_button.preferred_link)) {
                button_to_get_here = parent_button;
              }
            }
          };
          var find_same_button = function(b) { return b.board_id == button_to_get_here.board_id && b.id == button_to_get_here.id; };
          while(depth > 0) {
            button_to_get_here = null;
            allow_unpreferred = false;
            buttons.forEach(check_for_match);
            allow_unpreferred = true;
            buttons.forEach(check_for_match);
            if(!button_to_get_here) {
              // something bad happened
              depth = -1;
            } else {
              ref_button = button_to_get_here;
              depth = ref_button.depth;
              // check for loops, fail immediately
              if(path.find(find_same_button)) {
                depth = -1;
              } else {
                path.unshift(button_to_get_here);
              }
            }
            // hard limit on number of steps
            if(path.length > 15) {
              depth = -1;
            }
          }
          if(depth >= 0) {
            emberSet(button, 'pre_buttons', path);
            matching_buttons.push(button);
          }
        }
      }
    });

    var other_lookups = RSVP.resolve();

    var other_find_buttons = [];
    // TODO: include additional buttons if they are accessible from "home" or
    // the "sidebar" button sets.
    var home_board_id = stashes.get('temporary_root_board_state.id') || stashes.get('root_board_state.id') || (user && user.get('preferences.home_board.id'));

    if(include_home_and_sidebar && home_board_id) {
      other_lookups = new RSVP.Promise(function(lookup_resolve, lookup_reject) {
        var root_button_set_lookups = [];
        var button_sets = [];

        var lookup = function(key, home_lock) {
          var button_set = key && CoughDrop.store.peekRecord('buttonset', key);
          if(button_set) {
            button_set.set('home_lock_set', home_lock);
            button_sets.push(button_set);
          } else if(key) {
            root_button_set_lookups.push(CoughDrop.store.findRecord('buttonset', key).then(function(button_set) {
              button_set.set('home_lock_set', home_lock);
              button_sets.push(button_set);
            }, function() { return RSVP.resolve(); }));
          } else {
          }
        };
        if(home_board_id) {
          lookup(home_board_id);
        }
        (app_state.get('sidebar_boards') || []).forEach(function(brd) {
          lookup(brd.id, brd.home_lock);
        });
        RSVP.all_wait(root_button_set_lookups).then(function() {
          button_sets = Utils.uniq(button_sets, function(b) { return b.get('id'); });
          button_sets.forEach(function(button_set, idx) {
            var is_home = (idx === 0);
            if(button_set) {
              var promise = button_set.find_buttons(str).then(function(buttons) {
                buttons.forEach(function(button) {
                  button.meta_link = true;
                  button.on_this_board = false;
                  button.pre_buttons.unshift({
                    'id': -1,
                    'pre': is_home ? 'home' : 'sidebar',
                    'board_id': is_home ? 'home' : 'sidebar',
                    'board_key': is_home ? 'home' : 'sidebar',
                    'linked_board_id': button_set.get('id'),
                    'linked_board_key': button_set.get('key'),
                    'home_lock': button_set.get('home_lock_set'),
                    'label': is_home ? i18n.t('home', 'Home') : i18n.t('sidebar_board', "Sidebar, %{board_name}", {hash: {board_name: button_set.get('name')}})
                  });
                  matching_buttons.push(button);
                });
              });
              other_find_buttons.push(promise);
            }
          });
          lookup_resolve();
        }, function() {
          lookup_reject();
        });

      });
    }

    var other_buttons = other_lookups.then(function() {
      return RSVP.all_wait(other_find_buttons);
    });

    var image_lookups = other_buttons.then(function() {
      var image_lookup_promises = [];
      matching_buttons.forEach(function(button) {
        emberSet(button, 'current_depth', (button.pre_buttons || []).length);
        if(button.image && button.image.match(/^http/)) {
          emberSet(button, 'original_image', button.image);
          var promise = persistence.find_url(button.image, 'image').then(function(data_uri) {
            emberSet(button, 'image', data_uri);
          }, function() { });
          image_lookup_promises.push(promise);
          promise.then(null, function() { });
        }
      });
      return RSVP.all_wait(image_lookup_promises);
    });

    return image_lookups.then(function() {
      matching_buttons = matching_buttons.sort(function(a, b) {
        var a_depth = a.current_depth ? 1 : 0;
        var b_depth = b.current_depth ? 1 : 0;
        if(a_depth > b_depth) {
          return 1;
        } else if(a_depth < b_depth) {
          return -1;
        } else {
          if(a.label.toLowerCase() > b.label.toLowerCase()) {
            return 1;
          } else if(a.label.toLowerCase() < b.label.toLowerCase()) {
            return -1;
          } else {
            return 0;
          }
        }
      });
      matching_buttons = Utils.uniq(matching_buttons, function(b) { return (b.id || b.label) + "::" + b.board_id; });
      return matching_buttons;
    });
  }
});

export default CoughDrop.Buttonset;
