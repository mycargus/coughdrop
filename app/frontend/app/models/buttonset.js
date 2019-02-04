import Ember from 'ember';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import $ from 'jquery';
import RSVP from 'rsvp';
import DS from 'ember-data';
import CoughDrop from '../app';
import CoughDropImage from '../models/image';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';
import app_state from '../utils/app_state';
import stashes from '../utils/_stashes';
import word_suggestions from '../utils/word_suggestions';
import progress_tracker from '../utils/progress_tracker';
import Utils from '../utils/misc';

var button_set_cache = {};

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
  buttons_for_level: function(board_id, level) {
    var board_ids = {};
    var boards_to_check = [{id: board_id}];
    var buttons = this.get('buttons') || [];
    var count = 0;
    while(boards_to_check.length > 0) {
      var board_to_check = boards_to_check.shift();
      board_ids[board_to_check.id] = true;
      buttons.forEach(function(button) {
        if(button.board_id == board_to_check.id) {
          var visible = !button.hidden;
          var linked = !!button.link_disabled;
          if(button.visible_level) {
            visible = button.visible_level <= level;
          }
          if(button.linked_level) {
            linked = button.linked_level <= level;
          }
          if(visible) {
            if(button.linked_board_id && linked) {
              if(!board_ids[button.linked_board_id]) {
                console.log("adding" , button.linked_board_key, button);
                board_ids[button.linked_board_id] = true;
                boards_to_check.push({id: button.linked_board_id});
              }
            } else {
              count++;
            }
          }
        }
      });
    }
    return count;
  },
  redepth: function(from_board_id) {
    var buttons = this.get('buttons') || [];
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
    return buttons;
  },
  button_steps: function(start_board_id, end_board_id, map, home_board_id, sticky_board_id) {
    var last_board_id = end_board_id;
    var updated = true;
    if(sticky_board_id != home_board_id && sticky_board_id != start_board_id) {
      // TODO: consider route only needing a single-home to go through sticky board
    }
    if(start_board_id == end_board_id) {
      return {buttons: [], steps: 0, final_board_id: end_board_id};
    } else if(end_board_id == home_board_id) {
      return {buttons: [], steps: 1, pre: 'true_home', final_board_id: end_board_id};
    }
    var sequences = [{final_board_id: end_board_id, buttons: []}];
    while(updated) {
      var new_sequences = [];
      updated = false;
      sequences.forEach(function(seq) {
        var ups = map[(seq.buttons[0] || {board_id: seq.final_board_id}).board_id];
        if(seq.done) {
          new_sequences.push(seq);
        } else if(ups && ups.length > 0) {
          ups.forEach(function(btn) {
            var been_to_board = seq.buttons.find(function(b) { return b.board_id == btn.board_id; });
            if(!been_to_board && btn.board_id != btn.linked_board_id) {
              var new_seq = $.extend({}, seq);
              updated = true;
              new_seq.buttons = [].concat(new_seq.buttons);
              new_seq.buttons.unshift(btn);
              new_seq.steps = (new_seq.steps || 0) + 1;
              if(btn.home_lock) {
                new_seq.sticky_board_id = new_seq.sticky_board_id || btn.linked_board_id;
              }
              if(btn.board_id == start_board_id) {
                new_seq.done = true;
              } else if(btn.board_id == home_board_id && start_board_id != home_board_id) {
                new_seq.pre = 'true_home';
                new_seq.steps++;
                new_seq.done = true;
              }
              new_sequences.push(new_seq);
            }
          });
        }
      });
      sequences = new_sequences;
    }
    return sequences.sort(function(a, b) { return b.steps - a.steps; })[0];
  },
  board_map: function(button_sets) {
    var _this = this;
    var board_map = {};
    var buttons = [];
    button_sets.forEach(function(bs, idx) {
      var button_set_buttons = bs.get('buttons');
      if(bs == _this) {
        button_set_buttons = _this.redepth(bs.get('id'));
      }
      button_set_buttons.forEach(function(button) {
        if(!buttons.find(function(b) { return b.id == button.id && b.board_id == button.board_id; })) {
          if(!button.linked_board_id || button.force_vocalize || button.link_disabled) {
            buttons.push(button);
          }
        }
        if(button.linked_board_id && !button.link_disabled) {
          board_map[button.linked_board_id] = board_map[button.linked_board_id] || []
          if(!board_map[button.linked_board_id].find(function(b) { return b.id == button.id && b.board_id == button.board_id; })) {
            board_map[button.linked_board_id].push(button);
          }
        }
      })
    });
    return {buttons: buttons, map: board_map};
  },
  find_sequence: function(str, from_board_id, user, include_home_and_sidebar) {
    // TODO: consider optional support for keyboard for missing words
    if(str.length === 0) { return RSVP.resolve([]); }
    var query = str.toLowerCase();
    var _this = this;
    from_board_id = from_board_id || app_state.get('currentBoardState.id');
    var button_sets = [_this];
    var lookups = [RSVP.resolve()];
    var home_board_id = stashes.get('root_board_state.id') || (user && user.get('preferences.home_board.id'));
    //    var buttons = this.get('buttons') || [];

    if(include_home_and_sidebar) {
      // add those buttons and uniqify the buttons list
      var add_buttons = function(key, home_lock) {
        var button_set = key && CoughDrop.store.peekRecord('buttonset', key);
        if(button_set) {
          button_set.set('home_lock_set', home_lock);
          button_sets.push(button_set);
        } else if(key) {
          lookups.push(CoughDrop.Buttonset.load_button_set(key).then(function(button_set) {
            button_set.set('home_lock_set', home_lock);
            button_sets.push(button_set);
          }, function() { return RSVP.resolve(); }));
        }
      };
      // probably skip the sidebar for now, highlighting the scrollable sidebar
      // is kind of a can of worms
      add_buttons(home_board_id, false);
    }

    var partial_matches = [];
    var all_buttons_enabled = true;
    var parts = query.split(/\s+/);
    var cnt = 0;
    var buttons = [];
    var board_map = null;

    var build_map = RSVP.all_wait(lookups).then(function() {
      var res = _this.board_map(button_sets);
      buttons = res.buttons;
      board_map = res.map;
    });

    // check each button individually
    var button_sweep = build_map.then(function() {
//      console.log("all buttons", buttons, board_map);
      buttons.forEach(function(button, idx) {
        var lookups = [button.label, button.vocalization];
        var found_some = false;
        // check for a match on either the label or vocalization
        lookups.forEach(function(label) {
          if(found_some || !label) { return true; }
          var label_parts = label.toLowerCase().split(/\s+/);
          var jdx = 0;
          var running_totals = [];
          var total_edit_distance = 0;
          // iterate through all the parts of the query, looking for
          // any whole or partial matches
          parts.forEach(function(part, jdx) {
            // compare the first word in the button label
            // with each word in the query
            running_totals.push({
              keep_looking: true,
              start_part: jdx,
              next_part: jdx,
              label_part: 0,
              total_edit_distance: 0
            });
            running_totals.forEach(function(tot) {
              // if the label is still matching along the query
              // from where it started to the end of the label,
              // then add it as a partial match
              if(tot.keep_looking && tot.next_part == jdx) {
                if(!label_parts[tot.label_part]) {
                  // if the label is done, but there's more words
                  // in the query, we have a partial match
                } else {
                  // if we're not outside the bounds for edit
                  // distance, keep going for this starting point
                  var distance = word_suggestions.edit_distance(part, label_parts[tot.label_part]);
                  if(distance < Math.max(part.length, label_parts[tot.label_part].length) * 0.75) {
                    tot.label_part++;
                    tot.next_part++;
                    tot.total_edit_distance = tot.total_edit_distance + distance;
                  } else {
                    tot.keep_looking = false;
                  }
                }
                if(!label_parts[tot.label_part]) {
                  // if we got to the end of the label, we have a 
                  // partial match, otherwise there was more to 
                  // the label when the query ended, so no match
                  tot.valid = true;
                  tot.keep_looking = false;
                }
              }
            });
          });
          var matches = running_totals.filter(function(tot) { return tot.valid && tot.label_part == label_parts.length; });
          matches.forEach(function(match) {
            found_some = true;
            partial_matches.push({
              total_edit_distance: match.total_edit_distance,
              text: label,
              part_start: match.start_part,
              part_end: match.next_part,
              button: button
            });
          });
        });
      });
    });

    var sort_results = button_sweep.then(function() {
      partial_matches = partial_matches.sort(function(a, b) { 
        if(a.total_edit_distance == b.total_edit_distance) {
          return a.button.depth - b.button.depth;
        }
        return a.total_edit_distance - b.total_edit_distance; 
      });  
    });

    var combos = [{
      sequence: true, 
      text: "", 
      next_part: 0, 
      parts_covered: 0, 
      steps: [], 
      total_edit_distance: 0, 
      extra_steps: 0,
      current_sticky_board_id: stashes.get('temporary_root_board_state.id') || home_board_id
    }];
    var build_combos = sort_results.then(function() {
      // Check all permutations, score for shortest access distance
      // combined with shortest edit distance
      // for 1 part, include 30-50 matches
      // for 2 parts, include 20 matches per level
      // for 3 parts, include 10 matches per level
      // for 4 parts, include 5 matches per level
      // for 5 parts, include 3 matches per level
      var matches_per_level = Math.floor(Math.max(3, Math.min(1 / Math.log(parts.length / 1.4 - 0.17) * Math.log(100), 50)));
      console.log('matches', partial_matches);
      parts.forEach(function(part, part_idx) {
        var starters = partial_matches.filter(function(m) { return m.part_start == part_idx; });
        starters = starters.slice(0, matches_per_level);
        var new_combos = [];
        var combo_scores = [];
        combos.forEach(function(combo) {
          if(combo.next_part == part_idx) {
            starters.forEach(function(starter) {
              var dup = $.extend({}, combo);
              dup.steps = [].concat(dup.steps);
              var pre_id = (dup.steps[dup.steps.length - 1] || {}).board_id || from_board_id;
              // remember to expect auto-home if enabled for user and a prior button exists
              if(dup.steps.length > 0 && user && user.get('preferences.auto_home_return')) { pre_id = combo.current_sticky_board_id; }
              var button_steps = _this.button_steps(pre_id, starter.button.board_id, board_map, home_board_id, combo.current_sticky_board_id);
              if(button_steps) {
                var btn = $.extend({}, starter.button);
                btn.actual_button = true;
                dup.steps.push({sequence: button_steps, button: btn, board_id: button_steps.final_board_id});
                if(dup.steps.length > 1) { dup.multiple_steps = true; }
                dup.text = dup.text + (dup.text == "" ? "" : " ") + starter.text;
                dup.next_part = part_idx + (starter.part_end - starter.part_start);
                dup.parts_covered = dup.parts_covered + (starter.part_end - starter.part_start);
                dup.total_edit_distance = dup.total_edit_distance + starter.total_edit_distance;
                dup.extra_steps = dup.extra_steps + (button_steps.steps || 0);
                dup.total_steps = dup.steps.length + dup.extra_steps;
                if(button_steps.sticky_board_id) {
                  dup.current_sticky_board_id = button_steps.sticky_board_id;
                }
                new_combos.push(dup);
              }
            });
          } else {
            new_combos.push(combo);
          }
          // include what-if for skipping the current step,
          // as in, if I search for "I want to sleep" but the user 
          // doesn't have "to" then it should match for "I want sleep"
          // and preferably rank it higher than "I want top sleep", for example
          // (maybe add 1 edit distance point for dropped words)
          var dup = $.extend({}, combo);
          dup.next_part = part_idx + 1;
          new_combos.push(dup);
        });
        var cutoff = Math.floor(parts.length / 2);
        var parts_current_count = part_idx + 1;
        new_combos.forEach(function(combo) {
          // calculate match scores
          var primary_score = combo.total_edit_distance + (combo.extra_steps / (combo.parts_covered || 1) * 3);
          if(combo.total_edit_distance == 0) { primary_score = primary_score / 5; }
          combo.match_scores = [combo.total_edit_distance ? 1 : 0, combo.parts_covered == parts_current_count ? 0 : 1, combo.parts_covered > cutoff ? (parts_current_count - combo.parts_covered + primary_score) : 1000, parts_current_count - combo.parts_covered + primary_score, combo.steps.length];
        });
        // limit results as we go so we don't balloon memory usage
        combos = new_combos.sort(function(a, b) {
          for(var idx = 0; idx < a.match_scores.length; idx++) {
            if(a.match_scores[idx] != b.match_scores[idx]) {
              return a.match_scores[idx] - b.match_scores[idx];
            }
          }
          return 0;
        }).slice(0, 25 * (part_idx + 1));
      });
    });
    // when searching for "I want to sleep" sort as follows:
    // - I want to sleep
    // - I want sleep
    // - I want top sleep
    // - I walk to sleep
    // - want sleep
    // - want
    // - sleep
    // If there are enough errorless matches, show those first,
    // then sort results w/ >50% coverage by edit distance and steps
    // then sort the rest by edit distance and steps
    // then sort by number of words covered (bonus for > 50% coverage)
    // finally by number of button hits required
    var sort_combos = build_combos.then(function() {
      combos = combos.filter(function(c) { return c.text; });
      combos = combos.sort(function(a, b) {
        for(var idx = 0; idx < a.match_scores.length; idx++) {
          if(a.match_scores[idx] != b.match_scores[idx]) {
            return a.match_scores[idx] - b.match_scores[idx];
          }
        }
        return 0;
      });
      return combos.slice(0, 10);
    });

    var images = CoughDrop.store.peekAll('image');
    var image_lookups = sort_combos.then(function(combos) {
      var image_lookup_promises = [];
      combos.forEach(function(combo) {
        combo.steps.forEach(function(step) {
          var button = step.button;
          if(button) {
            var image = images.findBy('id', button.image_id);
            if(image) {
              button.image = image.get('best_url');
            }
            emberSet(button, 'image', emberGet(button, 'image') || Ember.templateHelpers.path('blank.png'));
            if(emberGet(button, 'image') && CoughDropImage.personalize_url) {
              emberSet(button, 'image', CoughDropImage.personalize_url(button.image, app_state.get('currentUser.user_token')));
            }
            emberSet(button, 'on_same_board', emberGet(button, 'steps') === 0);
  
            if(button.image && button.image.match(/^http/)) {
              emberSet(button, 'original_image', button.image);
              var promise = persistence.find_url(button.image, 'image').then(function(data_uri) {
                emberSet(button, 'image', data_uri);
              }, function() { });
              image_lookup_promises.push(promise);
              promise.then(null, function() { return RSVP.resolve() });
            }
          }
        });
      });
      return RSVP.all_wait(image_lookup_promises).then(function() {
        return combos;
      });
    });

    return image_lookups;
  },
  find_buttons: function(str, from_board_id, user, include_home_and_sidebar) {
    var matching_buttons = [];

    if(str.length === 0) { return RSVP.resolve([]); }
    var images = CoughDrop.store.peekAll('image');
    var _this = this;

    var traverse_buttons = new RSVP.Promise(function(traverse_resolve, traverse_reject) {
      var re = new RegExp("\\b" + str, 'i');
      var all_buttons_enabled = stashes.get('all_buttons_enabled');
      var buttons = _this.get('buttons') || [];
      if(from_board_id && from_board_id != _this.get('id')) {
        // re-depthify all the buttons based on the starting board
        buttons = _this.redepth(from_board_id);
      }
  
      buttons.forEach(function(button, idx) {
        // TODO: optionally show buttons on link-disabled boards
        if(!button.hidden || all_buttons_enabled) {
          var match_level = (button.label && button.label.match(re) && 3);
          match_level = match_level || (button.vocalization && button.vocalization.match(re) && 2);
          match_level = match_level || (button.label && word_suggestions.edit_distance(str, button.label) < Math.max(str.length, button.label.length) * 0.5 && 1);
          if(match_level) {
            button = $.extend({}, button, {match_level: match_level});
            button.on_this_board = (emberGet(button, 'depth') === 0);
            button.on_same_board = emberGet(button, 'on_this_board');
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
              button.pre_buttons = path;
              matching_buttons.push(button);
            }
          }
        }
      });
      traverse_resolve();
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
          var button_set = key && (button_set_cache[key] || CoughDrop.store.peekRecord('buttonset', key));
          if(button_set) {
            button_set.set('home_lock_set', home_lock);
            button_sets.push(button_set);
            button_set_cache[key] = button_set;
          } else if(key) {
            console.log("extra load!");
            root_button_set_lookups.push(CoughDrop.Buttonset.load_button_set(key).then(function(button_set) {
              button_set.set('home_lock_set', home_lock);
              button_sets.push(button_set);
              button_set_cache[key] = button_set;
            }, function() { return RSVP.resolve(); }));
          }
        };
        if(home_board_id) {
          lookup(home_board_id);
        }
        (app_state.get('sidebar_boards') || []).forEach(function(brd) {
          lookup(brd.id, brd.home_lock);
        });
        console.log("waiting on", root_button_set_lookups.length);
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

    var lookups_ready = traverse_buttons.then(function() {
      return other_lookups;
    })

    var other_buttons = lookups_ready.then(function() {
      return RSVP.all_wait(other_find_buttons);
    });

    var sort_results = other_buttons.then(function() {
      matching_buttons = matching_buttons.sort(function(a, b) {
        var a_depth = a.current_depth ? 1 : 0;
        var b_depth = b.current_depth ? 1 : 0;
        if(a_depth > b_depth) {
          return 1;
        } else if(a_depth < b_depth) {
          return -1;
        } else {
          if(a.match_level > b.match_level) {
            return -1;
          } else if(a.match_level < b.match_level) {
            return 1;
          } else {
            if(a.label.toLowerCase() > b.label.toLowerCase()) {
              return 1;
            } else if(a.label.toLowerCase() < b.label.toLowerCase()) {
              return -1;
            } else {
              return (a.current_depth || 0) - (b.current_depth || 0);
            }
          }
        }
      });
      matching_buttons = Utils.uniq(matching_buttons, function(b) { return (b.id || b.label) + "::" + b.board_id; });
      matching_buttons = matching_buttons.slice(0, 50);
    });
    var image_lookups = sort_results.then(function() {
      var image_lookup_promises = [];
      matching_buttons.forEach(function(button) {
        image_lookup_promises.push(CoughDrop.Buttonset.fix_image(button, images));
      });
      return RSVP.all_wait(image_lookup_promises);
    });


    return image_lookups.then(function() {
      return matching_buttons;
    });
  }
});

CoughDrop.Buttonset.fix_image = function(button, images) {
  if(button.image && CoughDropImage.personalize_url) {
    button.image = CoughDropImage.personalize_url(button.image, app_state.get('currentUser.user_token'));
  }
  var image = images.findBy('id', button.image_id);
  if(image) {
    button.image = image.get('best_url');
  }
  emberSet(button, 'image', emberGet(button, 'image') || Ember.templateHelpers.path('blank.png'));

  emberSet(button, 'current_depth', (button.pre_buttons || []).length);
  if(button.image && button.image.match(/^http/)) {
    emberSet(button, 'original_image', button.image);
    var promise = persistence.find_url(button.image, 'image').then(function(data_uri) {
      emberSet(button, 'image', data_uri);
    }, function() { });
    promise.then(null, function() { });
    return promise;
  }
  return RSVP.resolve();
};
CoughDrop.Buttonset.load_button_set = function(id) {
  var button_sets = CoughDrop.store.peekAll('buttonset');
  var found = CoughDrop.store.peekRecord('buttonset', id) || button_sets.find(function(bs) { return bs.get('key') == id; });
  if(!found) {
    button_sets.forEach(function(bs) {
      // TODO: check board keys in addition to board ids
      if((bs.get('board_ids') || []).indexOf(id) != -1 || bs.get('key') == id) {
        if(bs.get('fresh') || !found) {
          found = bs;
        }
      }
    });
  }
  if(found) { return RSVP.resolve(found); }
  
  var res = CoughDrop.store.findRecord('buttonset', id).then(function(button_set) {
    return button_set;
  }, function(err) {
    // if not found error, it may need to be regenerated
    if(err.error == 'Record not found' && err.id && err.id.match(/^\d/)) {
      return new RSVP.Promise(function(resolve, reject) {
        persistence.ajax('/api/v1/buttonsets/' + id + '/generate', {
          type: 'POST',
          data: { }
        }).then(function(data) {
          progress_tracker.track(data.progress, function(event) {
            if(event.status == 'errored') {
              reject({error: 'error while generating button set'});
            } else if(event.status == 'finished') {
              CoughDrop.store.findRecord('buttonset', id).then(function(button_set) {
                resolve(button_set);
              }, function(err) {
                reject({error: 'error while retrieving generated button set'});
              });
            }
          });
        }, function(err) {
          reject({error: "button set missing and could not be generated"});
        });
      });
    } else {
      return RSVP.reject(err);
    }
  });
  return res;
};

export default CoughDrop.Buttonset;
