import Ember from 'ember';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import { later as runLater, cancel as runCancel } from '@ember/runloop';
import $ from 'jquery';
import editManager from './edit_manager';
import modal from './modal';
import capabilities from './capabilities';
import app_state from './app_state';
import scanner from './scanner';
import stashes from './_stashes';
import frame_listener from './frame_listener';

// gotchas:
// - text boxes in edit mode should be clickable
// - backspace should only remove one item
// - PIN entry shouldn't double-add the selected number
// - identity dropdown should work, including picking an item in the
//   menu, and the menu auto-closing when somewhere else is hit
// - button_list should vocalize on select
// - hitting the action or image icon on a button while in edit
//   mode should open that mode, not general button settings
// - drag and drop to rearrange buttons should work
// - drag to clear/copy to stash should work
// - apply button from stash should work
// - click after short timeout even without mouseup should work
// - too-fast click should not work
// - painting should work
// - gaze_linger events should work
// - debounce should be honored
// - debounce should not apply for triple-click on clear
// - click/touch events should still work when in scanning mode
// - click/touch events should still work when in dwell tracking mode
// - keyboard events can add to the vocalization box
// - mouse cursor/joystick and control the dwell target
// - touch events on modal targets needs to work in speak mode

var $board_canvas = null;

$(document).on('mousedown touchstart', function(event) {
  if(buttonTracker.dwell_elem) {
    console.log("linger cleared because touch event");
    buttonTracker.clear_dwell();
    event.target = document.elementFromPoint(event.clientX, event.clientY);
  }
  buttonTracker.touch_start(event)  ;
  if(capabilities.mobile && event.type == 'touchstart' && app_state.get('speak_mode') && scanner.scanning) {
    scanner.listen_for_input();
  }
}).on('gazelinger mousemove touchmove mousedown touchstart', function(event) {
  if(event.type == 'mousemove' || event.type == 'mousedown') {
    buttonTracker.mouse_used = true;
  }
  buttonTracker.touch_continue(event);
}).on('mouseup touchend touchcancel blur', function(event) {
  if(capabilities.system == 'iOS' && !buttonTracker.ios_initialized) {
    var u = new window.SpeechSynthesisUtterance();
    u.text = "";
    window.speechSynthesis.speak(u);
    buttonTracker.ios_initialized = true;
  }
  if((event.type == 'mouseup' || event.type == 'touchend' || event.type == 'touchcancel') && buttonTracker.dwell_elem) {
    console.log("linger cleared because touch release event");
    buttonTracker.clear_dwell();
  }
  buttonTracker.touch_release(event);
}).on('keypress', '.button', function(event) {
  // basic keyboard navigation
  // if(app_state.get('edit_mode')) { return; }
  if(event.keyCode == 13 || event.keyCode == 32) {
    if(event.target.tagName != 'INPUT') {
      $(this).trigger('buttonselect');
    }
  }
}).on('keypress', '.integration_target', function(event) {
  // basic keyboard navigation
  if(event.keyCode == 13 || event.keyCode == 32) {
    frame_listener.trigger_target($(event.target).closest(".integration_target")[0]);
  }
}).on('keypress', function(event) {
  if(buttonTracker.check('keyboard_listen') && !buttonTracker.check('scanning_enabled') && !buttonTracker.check('dwell_enabled') && !modal.is_open()) {
    // add letter to the sentence box
    var key = "+" + event.key;
    if(event.key == ' ' || event.key == 'Enter') { key = ':space'; }
    app_state.activate_button({}, {
      label: event.key,
      vocalization: key,
      prevent_return: true,
      button_id: null,
      board: {id: 'external_keyboard', key: 'core/external_keyboard'},
      type: 'speak'
    });
  }
}).on('keydown', function(event) {
  if(event.keyCode == 9) { // tab
    $board_canvas = $("#board_canvas");
    if(!$board_canvas.data('focus_listener_set')) {
      $board_canvas.data('focus_listener_set', true);
      $board_canvas.on('focus', function(event) {
        // TODO: need a reliable way to figure out if this is getting reverse-tabbed into
        buttonTracker.focus_tab(true);
      });
    }
    if(event.target.tagName == 'CANVAS') {
      var handled = buttonTracker.move_tab(!event.shiftKey);
      if(handled) {
        event.preventDefault();
      }
    } else {
      buttonTracker.clear_tab();
    }
  } else if(event.keyCode == 13 || event.keyCode == 32) { // return
    if(event.target.tagName == 'CANVAS') {
      buttonTracker.select_tab();
    }
  } else if(event.keyCode == 27) { // esc
    if(modal.is_open() && modal.is_closeable()) {// && (event.target.tagName == 'INPUT' || event.target.tagName == 'BUTTON' || event.target.tagName == 'TEXTAREA' || event.target.tagName == 'A')) {
      modal.close();
    } else if(buttonTracker.check('keyboard_listen') && !modal.is_open()) {
      app_state.activate_button({vocalization: ':clear'}, {
        label: 'escape',
        vocalization: ':clear',
        prevent_return: true,
        button_id: null,
        board: {id: 'external_keyboard', key: 'core/external_keyboard'},
        type: 'speak'
      });
    }
  } else if(event.keyCode == 8) { // backspace
    if(buttonTracker.check('keyboard_listen') && !modal.is_open()) {
      app_state.activate_button({vocalization: ':backspace'}, {
        label: 'escape',
        vocalization: ':backspace',
        prevent_return: true,
        button_id: null,
        board: {id: 'external_keyboard', key: 'core/external_keyboard'},
        type: 'speak'
      });
    }
  } else if([37, 38, 39, 40].indexOf(event.keyCode) != -1) {
    buttonTracker.direction_event(event);
  }
}).on('keyup', function(event) {
  if([37, 38, 39, 40].indexOf(event.keyCode) != -1) {
    buttonTracker.direction_event(event);
  }
}).on('keydown', function(event) {
  if(buttonTracker.check('dwell_enabled') && buttonTracker.check('select_keycode') && buttonTracker.check('dwell_selection') == 'button') {
    if(event.keyCode && event.keyCode == buttonTracker.check('select_keycode')) {
      if(buttonTracker.last_dwell_linger) {
        var events = buttonTracker.last_dwell_linger.events;
        var e = events[events.length - 1];
        buttonTracker.element_release(buttonTracker.last_dwell_linger, e);
      }
    }
  }
  if(!buttonTracker.check('scanning_enabled')) { return; }
  if(event.keyCode && event.keyCode == buttonTracker.check('select_keycode')) { // spacebar key
    scanner.pick();
    event.preventDefault();
  } else if(event.keyCode && buttonTracker.check('any_select')) {
    scanner.pick();
    event.preventDefault();
  } else if(event.keyCode && event.keyCode == buttonTracker.check('next_keycode')) { // 1 key
    scanner.next();
    event.preventDefault();
  }
}).on('gazedwell', function(event) {
  var element_wrap = buttonTracker.find_selectable_under_event(event);
  buttonTracker.frame_event(event, 'select');
  if(element_wrap && element_wrap.button) {
    element_wrap.trigger('buttonselect');
  } else {
    $(this).trigger('click');
  }
}).on('keypress', '#button_list', function(event) {
  if(event.keyCode == 13 || event.keyCode == 32) {
    $(this).trigger('select');
  }
}).on('drop', '.button,.board_drop', function(event) {
  event.preventDefault();
  $('.button.drop_target,.board_drop.drop_target').removeClass('drop_target');
}).on('dragover', '.button', function(event) {
  event.preventDefault();
  if(app_state.get('edit_mode')) {
    $(this).addClass('drop_target');
  }
}).on('dragover', '.board_drop', function(event) {
  event.preventDefault();
  $(this).addClass('drop_target');
}).on('dragleave', '.button,.board_drop', function(event) {
  event.preventDefault();
  $(this).removeClass('drop_target');
}).on('mousedown touchstart', '.select_on_click', function(event) {
  $(this).focus().select();
  event.preventDefault();
});
$(document).on('click', "a[target='_blank']", function(event) {
  if(capabilities.installed_app) {
    event.preventDefault();
    capabilities.window_open(event.target.href, '_system');
  }
});
$(window).on('blur', function(event) {
  runCancel(buttonTracker.linger_clear_later);
  runCancel(buttonTracker.linger_close_enough_later);
});

var buttonTracker = EmberObject.extend({
  setup: function() {
    // cheap trick to get us ahead of the line in front of ember
    $("#within_ember").on('click', '.advanced_selection', function(event) {
      // we're basically replacing all click events by tracking up and down explicitly,
      // so we don't want any unintentional double-triggers
      if(event.pass_through) { return; }
      event.preventDefault();
      event.stopPropagation();
      // skip the ember listeners, but pass along for bootstrap dropdowns
      if($(event.target).closest('.dropdown').length === 0) {
        $(document).trigger($.Event(event));
      }
    });
  },
  check: function(attr) {
    if(app_state.get('speak_mode')) {
      return buttonTracker[attr];
    } else {
      return null;
    }
  },
  touch_start: function(event) {
    // advanced_selection regions should be eating all click events and
    // instead manually interpreting touch and mouse events. that way we
    // can do magical things like "click" on starting/ending point
    if($(event.target).closest('.advanced_selection').length > 0) {
      // doesn't need to be here, but since buttons are always using advanced_selection it's probably ok
      $(".touched").removeClass('touched');
      // this is to prevent ugly selected boxes that happen with dragging
      if(app_state.get('edit_mode') || app_state.get('speak_mode')) {
        if(!buttonTracker.ignored_region(event) && event.type == 'mousedown') {
          event.preventDefault();
        }
        if(app_state.get('edit_mode')) {
          return;
        }
      }

      buttonTracker.stop_dragging();
      // track the starting point because we may be using it as the "click"
      // location, depending on the user's settings
      var button_wrap = buttonTracker.find_selectable_under_event(event);
      buttonTracker.initialTarget = button_wrap;
      buttonTracker.initialEvent = event;
      if(buttonTracker.initialTarget) {
        buttonTracker.initialTarget.timestamp = (new Date()).getTime();
        buttonTracker.initialTarget.event = event;
      }
      // doesn't need to be here, but since buttons are always using advanced_selection it's probably ok
      if(button_wrap) {
        button_wrap.addClass('touched');
      } else {
        app_state.get('board_virtual_dom').clear_touched();
      }
    } else {
      buttonTracker.triggerEvent = event;
    }
  },
  // used for handling dragging, scanning selection
  touch_continue: function(event) {
    if(buttonTracker.transitioning) {
      event.preventDefault();
      return;
    }

    // not the best approach, but I was getting tired of all the selected text blue things when
    // testing dragging so I threw this in.
    if(buttonTracker.buttonDown && app_state.get('edit_mode') && (buttonTracker.drag || !buttonTracker.ignored_region(event))) {
      // TODO: this lookup should be a method instead of being hard-coded, like ignored_region
      if($(event.target).closest("#sidebar,.modal").length === 0) {
        event.preventDefault();
      }
    }

    event = buttonTracker.normalize_event(event);
    // We disable ignoreUp on continued movement because... I don't know why. This needs a comment.
    buttonTracker.ignoreUp = false;
    if(event.screenX && event.clientX) {
      window.screenInnerOffsetY = event.screenY - event.clientY;
      window.screenInnerOffsetX = event.screenX - event.clientX;
      stashes.persist('screenInnerOffsetX', window.screenInnerOffsetX);
      stashes.persist('screenInnerOffsetY', window.screenInnerOffsetY);
    }
    if(event.type == 'touchstart' || event.type == 'mousedown' || event.type == 'touchmove') {
      buttonTracker.buttonDown = true;
    } else if(event.type == 'gazelinger' && buttonTracker.check('dwell_enabled')) {
      buttonTracker.dwell_linger(event);
    } else if(event.type == 'mousemove' && buttonTracker.check('dwell_enabled') && buttonTracker.check('dwell_type') == 'mouse_dwell') {
      buttonTracker.dwell_linger(event);
    }
    if(['gazelinger', 'mousemove', 'touchmove', 'scanover'].indexOf(event.type) != -1) {
      buttonTracker.frame_event(event, 'over');
    } else if(['mousedown', 'touchstart'].indexOf(event.type) != -1) {
      buttonTracker.frame_event(event, 'start');
    }
    if(!buttonTracker.buttonDown && !app_state.get('edit_mode')) {
      var button_wrap = buttonTracker.find_selectable_under_event(event);
      if(button_wrap) {
        button_wrap.addClass('hover');
        // TODO: this is not terribly performant, but I guess it doesn't matter
        // since it won't trigger much on mobile
        $("#board_canvas").css('cursor', 'pointer');
        if(app_state.get('default_mode') && button_wrap.dom) {
          var $stash_hover = $("#stash_hover");
          if($stash_hover.data('button_id') != button_wrap.id) {
            var offset = $(button_wrap.dom).offset();
            var window_width = $(window).width();
            if(offset && offset.left) {
              $stash_hover.removeClass('on_button');
              $stash_hover.removeClass('right_side');
              $stash_hover.detach();
              if(offset.left > window_width - 165) {
                $stash_hover.css({
                  top: offset.top,
                  left: window_width - 165
                });
              } else {
                $stash_hover.css({
                  top: offset.top,
                  left: offset.left
                });
              }
              $(".board").before($stash_hover);
              runLater(function() {
                $stash_hover.addClass('on_button');
                editManager.stashed_button_id = button_wrap.id;
              });
            }
            $stash_hover.data('button_id', button_wrap.id);
          }
        }
      } else {
        if($(event.target).closest("#stash_hover").length === 0) {
          $("#stash_hover").removeClass('on_button').data('button_id', null);
        }
        app_state.get('board_virtual_dom').clear_hover();
        $("#board_canvas").css('cursor', '');
      }
      return;
    }

    if(buttonTracker.buttonDown && buttonTracker.check('any_select') && buttonTracker.check('scanning_enabled')) {
      if(event.type != 'mousedown' && event.type != 'touchstart') {
        // ignore scanning events when checking for element release
        event.preventDefault();
        buttonTracker.ignoreUp = true;
        return false;
      }
      var override_allowed = false;
      if(event.type == 'mousedown') {
        if($(event.target).closest("#identity_button,#exit_speak_mode").length > 0) {
          override_allowed = true;
        }
      }
      if(!override_allowed) {
        // allow selection events to pass through even when scanning if on identity
        buttonTracker.ignoreUp = true;
      }
      var now = (new Date()).getTime();
      if(event.type == 'mousedown' && buttonTracker.last_scanner_select && (now - buttonTracker.last_scanner_select) < 500) {
        return false;
      } else {
        if(event.type == 'touchstart') {
          buttonTracker.last_scanner_select = now;
        }
        var width = $(window).width();
        if(event.clientX <= (width / 2)) {
          if(buttonTracker.check('left_screen_action') == 'next') {
            return scanner.next();
          } else {
            return scanner.pick();
          }
        } else {
          if(buttonTracker.check('') == 'next') {
            return scanner.next();
          } else {
            return scanner.pick();
          }
        }
      }
    }
    if(buttonTracker.buttonDown && !$(event.target).hasClass('highlight')) {
      modal.close_highlight();
    }
    if(buttonTracker.buttonDown && editManager.paint_mode) {
      // touch drag events don't return the right 'this'.
      var elem_wrap = buttonTracker.button_from_point(event.clientX, event.clientY);
      var elem = document.elementFromPoint(event.clientX, event.clientY);
      if(elem_wrap && $(elem).closest(".board").length > 0) {
        event.preventDefault();
        event.stopPropagation();
        elem_wrap.trigger('buttonpaint');
      }
    } else if(buttonTracker.buttonDown) {
      var elem_wrap = buttonTracker.track_drag(event);
      if(event.type == 'touchstart' || event.type == 'mousedown') {
        buttonTracker.longPressEvent = event;
        runCancel(buttonTracker.track_long_press.later);
        runCancel(buttonTracker.track_short_press.later);
        if(buttonTracker.check('long_press_delay')) {
          buttonTracker.track_long_press.later = runLater(buttonTracker, buttonTracker.track_long_press, buttonTracker.long_press_delay);
        }
        if(buttonTracker.check('short_press_delay')) {
          buttonTracker.track_short_press.later = runLater(buttonTracker, buttonTracker.track_short_press, buttonTracker.short_press_delay);
        }
      } else {
        buttonTracker.longPressEvent = null;
      }
      $('.drag_button.btn-danger').removeClass('btn-danger');
      $('.drag_button.btn-info').removeClass('btn-info');
      if(buttonTracker.drag) {
        buttonTracker.drag.hide();
        var under = document.elementFromPoint(event.clientX, event.clientY);
        buttonTracker.drag.show();
        if(under) {
          if(under.id == 'edit_stash_button') {
            $(under).addClass('btn-info');
          } else if(under.id == 'edit_clear_button') {
            $(under).addClass('btn-danger');
          }
        }
      }

      buttonTracker.multi_touch = buttonTracker.multi_touch || {total: 0, multis: 0};
      buttonTracker.multi_touch.total++;
      if(event.type != 'gazelinger' && event.total_touches && event.total_touches > 1) {
        buttonTracker.multi_touch.multis++;
      }

      if(!elem_wrap || !app_state.get('edit_mode')) {
      } else {
        // this is expensive, only do when the drop target has changed
        if(elem_wrap.dom && elem_wrap.dom != buttonTracker.drag.data('over')) {
          // clear existing placeholder if one already exists
          if(buttonTracker.drag.data('over')) {
            var $elem = $(buttonTracker.drag.data('elem'));
            var $over = $(buttonTracker.drag.data('over'));
            var $overClone = $(buttonTracker.drag.data('overClone'));
            $overClone.remove();
            $over.css('opacity', 1.0);
            // if back to original state then clear target settings
            if(elem_wrap.dom == buttonTracker.drag.data('elem')) {
              buttonTracker.drag.data('over', null);
              buttonTracker.drag.data('overClone', null);
              $elem.show();
            }
          }
          // remember which element you were last over, can skip all this if hasn't changed
          buttonTracker.drag.data('over', elem_wrap.dom);

          // $over is the current drop target, make a copy of it and put it in as a
          // placeholder where the dragged button used to live
          var $over = $(elem_wrap.dom);
          var for_folder = $over.find(".action_container.folder").length > 0;
          var $overClone = null;
          try {
            $overClone = $over.clone();
          } catch(e) { }
          if($overClone) {
            if(elem_wrap.dom == buttonTracker.drag.data('elem')) {
              $overClone.css('opacity', 0.0);
            } else {
              var opacity = for_folder ? 0.2 : 0.7;
              $overClone.css('opacity', opacity);
            }
            buttonTracker.drag.data('overClone', $overClone[0]);
            var $elem = $(buttonTracker.drag.data('elem'));
            if(!for_folder) {
              $over.css('opacity', 0.0);
            }
            $overClone.css({
              top: $elem.css('top'),
              left: $elem.css('left')
            });
            $elem.hide().after($overClone);
          }
        }
      }
      if(buttonTracker.drag) {
        buttonTracker.drag.css({position: 'absolute', left: event.pageX + buttonTracker.buttonAdjustX, top: event.pageY + buttonTracker.buttonAdjustY});
      }
    }
  },
  touch_release: function(event) {
    event = buttonTracker.normalize_event(event);

    // don't remember why this is important...
    buttonTracker.buttonDown = false;

    var selectable_wrap = buttonTracker.find_selectable_under_event(event);
    // if dragging a button, behavior is very different than otherwise
    if(buttonTracker.drag) {
      // hide the dragged button for a second to find what's underneath it
      buttonTracker.drag.hide();
      var under = document.elementFromPoint(event.clientX, event.clientY);
      // check to see if the button was dragged to one of the helps at the top
      if(under) {
        if(under.id == 'edit_clear_button') {
          $(buttonTracker.drag.data('elem')).trigger('clear');
        } else if(under.id == 'edit_stash_button') {
          $(buttonTracker.drag.data('elem')).trigger('stash');
        }
      }
      // remove the hover, stop hiding the original
      if(buttonTracker.drag.data('over')) {
        var $over = $(buttonTracker.drag.data('over'));
        var $overClone = $(buttonTracker.drag.data('overClone'));
        $overClone.remove();
        $over.css('opacity', 1.0);
      }
      $(buttonTracker.drag.data('elem')).css('opacity', 1.0).show();
      buttonTracker.drag.remove();
      // if it's on a different button, trigger the swap event
      var button_wrap = buttonTracker.find_button_under_event(event);
      if(button_wrap) {
        var dragId = buttonTracker.drag.attr('data-id');
        var dropId = button_wrap.id;
        button_wrap.data('drag_id', dragId);
        button_wrap.data('drop_id', dropId);
        button_wrap.trigger('rearrange');
      }
      buttonTracker.drag = null;
    } else if((selectable_wrap || buttonTracker.initialTarget) && !buttonTracker.ignored_region(event)) {
      // if it either started or ended on a selectable item then there's a
      // chance we need to trigger a 'click', so pass it along
      buttonTracker.buttonDown = true;
      buttonTracker.element_release(selectable_wrap, event);
//     } else if(event.type == 'touchend' && event.target.tagName == 'A' || event.target.tagName == 'BUTTON') {
//       event.preventDefault();
//       event.stopPropagation();
//       $(event.target).trigger('click');
    // TODO: if not advanced_selection, touch events (but not mouse events) should be
    // mapped to click events for faster activation. Maybe find a library for this..
    } else {
      buttonTracker.frame_event(event, 'select');
    }
    editManager.release_stroke();
    buttonTracker.stop_dragging();
    buttonTracker.initialTarget = null;
    buttonTracker.initialEvent = null;
    app_state.get('board_virtual_dom').clear_touched();
    $('.touched').removeClass('touched');
  },
  element_release: function(elem_wrap, event) {
    // don't remember why this is important, but I'm pretty sure it is
    if(buttonTracker.ignored_region(event)) {
      if(editManager.finding_target()) {
        // when finding a target, ignore the release event
        buttonTracker.ignoreUp = true;
        event.preventDefault();
      } else {
        return;
      }
    }

    if(buttonTracker.drag || !buttonTracker.buttonDown || buttonTracker.ignoreUp) {
      // when dragging or nothing selected, do nothing
      event.preventDefault();
      buttonTracker.ignoreUp = false;
    } else if(editManager.finding_target()) {
      event.preventDefault();
      // if looking for a target and one is found, hit it
      if(((elem_wrap && elem_wrap.dom && elem_wrap.dom.className) || "").match(/button/)) {
        buttonTracker.button_release(elem_wrap, event);
      }
      // TODO: clear finding_target when selecting anywhere else, leaving edit mode, etc.
    } else if(buttonTracker.ignored_region(event) || buttonTracker.ignored_region(buttonTracker.startEvent)) {
      // if it's an ignored region, do nothing
    } else if(!app_state.get('edit_mode')) {
      // when not editing, use user's preferred selection logic for identifying and
      // selecting a button
      event.preventDefault();
      var frame_event = event;
      var ts = (new Date()).getTime();

      if(event.type != 'gazelinger' && !event.dwell_linger) {
        // Use start, end or average pointer location for selection
        buttonTracker.activation_location = buttonTracker.activation_location || window.user_preferences.any_user.activation_location;
        if(buttonTracker.activation_location == 'start') {
          elem_wrap = buttonTracker.initialTarget;
          frame_event = buttonTracker.initialEvent;
        } else if(buttonTracker.activation_location == 'average') {
          // TODO: implement weighted average. Sample pointer location
          // from start to release and find the most likely target, ideally
          // taking into account distance from center of each potential target.
        } else {
          if($(event.target).closest('.advanced_selection') === 0) {
            return;
          }
        }
        // ignore presses that are too short
        if(buttonTracker.check('minimum_press') && buttonTracker.initialTarget && (ts - buttonTracker.initialTarget.timestamp) < buttonTracker.minimum_press) {
          elem_wrap = null;
        }
      }
      buttonTracker.frame_event(frame_event, 'select');

      buttonTracker.multi_touch = buttonTracker.multi_touch || {total: 0, multis: 0};
      buttonTracker.multi_touch.total++;
      if(event.type != 'gazelinger' && event.total_touches && event.total_touches > 1) {
        buttonTracker.multi_touch.multis++;
      }

      // logic to prevent quick double-tap, seems like this was a fix for iOS problems
      // but it may no longer be necessary
      if(elem_wrap && elem_wrap.dom && buttonTracker.lastSelect != elem_wrap.dom) {
        event.preventDefault();
        if(elem_wrap.dom.id != 'clear_button') {
          buttonTracker.lastSelect = elem_wrap.dom;
          buttonTracker.clear_hits = 0;
          runLater(function() {
            if(buttonTracker.lastSelect == elem_wrap.dom) {
              buttonTracker.lastSelect = null;
            }
          }, 300);
        }
        var event_type = 'mouse';
        if(event.type && event.type.match(/touch/)) { event_type = 'touch'; }
        if(event.dwell_linger || (event.type && event.type.match(/gaze/))) { event_type = 'dwell'; }
        var track = buttonTracker.track_selection({
          event_type: event.type,
          selection_type: event_type,
          total_events: buttonTracker.multi_touch.total,
          multi_touch_events: buttonTracker.multi_touch.multis
        });

        // selection events can be prevented by a debounce setting
        if(track.proceed) {
          // different elements have different selection styles
          // TODO: standardize this more
          if(elem_wrap.dom.id == 'identity') {
            event.preventDefault();
            // click events are eaten by our listener above, unless you
            // explicitly tell it to pass them through
            var e = $.Event( "click" );
            e.clientX = event.clientX;
            e.clientY = event.clientY;
            e.pass_through = true;
            $(elem_wrap.dom).trigger(e);
          } else if(elem_wrap.dom.id == 'button_list') {
            event.preventDefault();
            var $elem = $(elem_wrap.dom);
            $elem.addClass('focus');
            runLater(function() {
              $elem.removeClass('focus');
            }, 500);
            $elem.trigger('select');
          } else if(elem_wrap.dom.tagName == 'A' && $(elem_wrap.dom).closest('#pin').length > 0) {
            event.preventDefault();
            $(elem_wrap.dom).trigger('select');
          } else if((elem_wrap.dom.className || "").match(/button/) || elem_wrap.virtual_button) {
            buttonTracker.button_release(elem_wrap, event);
          } else if(elem_wrap.dom.classList.contains('integration_target')) {
            frame_listener.trigger_target(elem_wrap.dom);
          } else {
            event.preventDefault();
            // click events are eaten by our listener above, unless you
            // explicitly tell it to pass them through
            var e = $.Event( "click" );
            e.clientX = event.clientX;
            e.clientY = event.clientY;
            e.pass_through = true;
            $(elem_wrap.dom).trigger(e);
          }
        }

        // clear multi-touch for modeling can ignore debounces
        if(elem_wrap.dom.id == 'clear_button' && event.type != 'gazelinger') {
          buttonTracker.clear_hits = (buttonTracker.clear_hits || 0) + 1;
          runCancel(buttonTracker.clear_hits_timeout);
          buttonTracker.clear_hits_timeout = runLater(function() {
            buttonTracker.clear_hits = 0;
          }, 1500);
          if(buttonTracker.clear_hits >= 3) {
            buttonTracker.clear_hits = 0;
            var e = $.Event('tripleclick');
            e.clientX = event.clientX;
            e.clientY = event.clientY;
            e.pass_through = true;
            $(elem_wrap.dom).trigger(e);
          }
        }
      }
    } else if(app_state.get('edit_mode') && !editManager.paint_mode) {
      if(((elem_wrap && elem_wrap.dom && elem_wrap.dom.className) || "").match(/button/)) {
        buttonTracker.button_release(elem_wrap, event);
      }
    }

    // without this, applying a button from the stash causes the selected
    // button to be put in drag mode
    buttonTracker.buttonDown = false;
    buttonTracker.multi_touch = null;
  },
  button_release: function(elem_wrap, event) {
    // buttons have a slightly-more advanced logic, because of all the selection
    // targets available in edit mode (image, action button, etc.) and the option
    // of applying stashed buttons/swapping buttons
    var $target = $(event.target);
    if(editManager.finding_target()) {
      elem_wrap.trigger('buttonselect');
    } else if(!app_state.get('edit_mode')) {
      elem_wrap.trigger_special('buttonselect', {clientX: event.clientX, clientY: event.clientY});
    } else if(app_state.get('edit_mode') && !editManager.paint_mode) {
      event.preventDefault();
      if($target.closest('.action').length > 0) {
        elem_wrap.trigger('actionselect');
      } else if($target.closest('.symbol').length > 0) {
        elem_wrap.trigger('symbolselect');
      } else {
        elem_wrap.trigger('buttonselect');
      }
    }
  },
  update_gamepads: function() {
    var gamepads = navigator.getGamepads ? navigator.getGamepads() : (navigator.webkitGetGamepads ? navigator.webkitGetGamepads : []);
    buttonTracker.gamepads = {};
    for (var i = 0; i < gamepads.length; i++) {
      var gp = gamepads[i];
      if (gp) {
        buttonTracker.gamepads[gp.id] = gp;
      }
    }
  },
  direction_event: function(event) {
    buttonTracker.direction_keys = buttonTracker.direction_keys || {};
    buttonTracker.gamepad_down_buttons = buttonTracker.gamepad_down_buttons || {};
    if(event.type == 'keydown' && event.keyCode) {
      buttonTracker.direction_keys[event.keyCode] = (new Date()).getTime();
    } else if(event.type == 'keyup' && event.keyCode) {
      buttonTracker.direction_keys[event.keyCode] = false;
    }
    if(buttonTracker.check('dwell_type') != 'arrow_dwell') {
      return;
    }
    if(!buttonTracker.handle_direction) {
      // workaround for cordova plugin using older version of button api
      var pressed = function(button) {
        if(button && (typeof button['value'] !== 'undefined')) {
          return button.value == 1.0;
        } else {
          return button == 1.0;
        }
      };
      buttonTracker.handle_direction = function() {
        // up:    key 38, buttons[12], axes[1] == -1, axes[3] == -1
        // down:  key 40, buttons[13], axes[1] == 1, axes[3] == 1
        // left:  key 37, buttons[14], axes[0] == -1, axes[2] == -1
        // right: key 39, buttons[15], axes[0] == 1, axes[2] == 1
        // select: buttons[0-3] (abxy), buttons[4,6] (L), buttons[5,7] (R), buttons[9] (start), buttons[10,11] (joysticks)
        var x = buttonTracker.direction_x || (window.innerWidth / 2);
        var y = buttonTracker.direction_y || (window.innerHeight / 2);
        var update = false;
        var pad_actions = {};
        if (!('ongamepadconnected' in window)) {
          buttonTracker.update_gamepads();
        }
        var gamepads = buttonTracker.gamepads || {};
        var codes = [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11];
        for(var id in gamepads) {
          var pad = gamepads[id];
          if(pad.connected) {
            if(pad.axes[0] > 0.9 || pad.axes[2] > 0.9 || pressed(pad.buttons[15])) {
              pad_actions.right = 2.0;
            } else if(pad.axes[0] > 0.7 || pad.axes[2] > 0.7) {
              pad_actions.right = 1.0;
            } else if(pad.axes[0] > 0.5 || pad.axes[2] > 0.5) {
              pad_actions.right = 0.5;
            }
            if(pad.axes[0] < -0.9 || pad.axes[2] < -0.9 || pressed(pad.buttons[14])) {
              pad_actions.left = 2.0;
            } else if(pad.axes[0] < -0.7 || pad.axes[2] < -0.7) {
              pad_actions.left = 1.0;
            } else if(pad.axes[0] < -0.5 || pad.axes[2] < -0.5) {
              pad_actions.left = 0.5;
            }
            var up_axis_2 = (pad.axes.length > 4) ? 5 : 3;
            if(pad.axes[1] < -0.9 || pad.axes[up_axis_2] < -0.9 || pressed(pad.buttons[12])) {
              pad_actions.up = 2.0;
            } else if(pad.axes[1] < -0.7 || pad.axes[up_axis_2] < -0.7) {
              pad_actions.up = 1.0;
            } else if(pad.axes[1] < -0.5 || pad.axes[up_axis_2] < -0.5) {
              pad_actions.up = 0.5;
            }
            if(pad.axes[1] > 0.9 || pad.axes[up_axis_2] > 0.9 || pressed(pad.buttons[13])) {
              pad_actions.down = 2.0;
            } else if(pad.axes[1] > 0.7 || pad.axes[up_axis_2] > 0.7) {
              pad_actions.down = 1.0;
            } else if(pad.axes[1] > 0.5 || pad.axes[up_axis_2] > 0.5) {
              pad_actions.down = 0.5;
            }
            for(var idx = 0; idx < codes.length; idx++) {
              var code = codes[idx];
              var ref = pad.id.toString() + ":" + code;
              if(pressed(pad.buttons[code])) {
                if(!buttonTracker.gamepad_down_buttons[ref]) {
                  buttonTracker.gamepad_down_buttons[ref] = true;
                  pad_actions.select = true;
                }
              } else {
                buttonTracker.gamepad_down_buttons[ref] = false;
              }

            }
          }
        }
        var rate = 1.0;
        if(buttonTracker.dwell_arrow_speed == 'moderate') {
          rate = 2.5;
        } else if(buttonTracker.dwell_arrow_speed == 'quick') {
          rate = 4.0;
        } else if(buttonTracker.dwell_arrow_speed == 'speedy') {
          rate = 6.0;
        } else if(buttonTracker.dwell_arrow_speed == 'really_slow') {
          rate = 0.5;
        }
        if(buttonTracker.direction_keys[37] || pad_actions.left) {
          if(buttonTracker.direction_keys[39] && buttonTracker.direction_keys[39] > buttonTracker.direction_keys[37]) {
            // if right was pressed more recently than left, ignore left
          } else if(x > 0) {
            x = x - ((pad_actions.left || 2.0) * rate);
            update = true;
          }
        }
        if(buttonTracker.direction_keys[39] || pad_actions.right) {
          if(buttonTracker.direction_keys[37] && buttonTracker.direction_keys[37] > buttonTracker.direction_keys[39]) {
            // if left was pressed more recently than right, ignore right
          } else if(x < window.innerWidth) {
            x = x + ((pad_actions.right || 2.0) * rate);
            update = true;
          }
        }
        if(buttonTracker.direction_keys[38] || pad_actions.up) {
          if(buttonTracker.direction_keys[40] && buttonTracker.direction_keys[40] > buttonTracker.direction_keys[38]) {
            // if down was pressed more recently than up, ignore up
          } else if(y > 0) {
            y = y - ((pad_actions.up || 2.0) * rate);
            update = true;
          }
        }
        if(buttonTracker.direction_keys[40] || pad_actions.down) {
          if(buttonTracker.direction_keys[38] && buttonTracker.direction_keys[38] > buttonTracker.direction_keys[40]) {
            // if up was pressed more recently than down, ignore down
          } else if(y < window.innerHeight) {
            y = y + ((pad_actions.down || 2.0) * rate);
            update = true;
          }
        }
        if(pad_actions.select) {
          // Only if this is a new button pressed (and one that happened after
          // a directional movement of some kind) should we count it as a selection
          if(buttonTracker.direction_x !== undefined && buttonTracker.direction_y !== undefined) {
            // trigger a select action
            if(buttonTracker.last_dwell_linger && buttonTracker.last_dwell_linger.events) {
              var events = buttonTracker.last_dwell_linger.events;
              var e = events[events.length - 1];
              buttonTracker.element_release(buttonTracker.last_dwell_linger, e);
            }
          }
        }
        if(update) {
          buttonTracker.direction_x = x;
          buttonTracker.direction_y = y;
          var e = $.Event( 'gazelinger' );
          e.clientX = x;
          e.clientY = y;
          $(document).trigger(e);
        }
        if(Object.keys(gamepads).length > 0 || Object.keys(buttonTracker.direction_keys).length > 0) {
          window.requestAnimationFrame(buttonTracker.handle_direction);
        } else {
          buttonTracker.handle_direction = null;
        }
      };
      window.requestAnimationFrame(buttonTracker.handle_direction);
    }
  },
  dwell_linger: function(event) {
    // debounce, waiting for clearance
    if(buttonTracker.dwell_wait) { console.log("linger waiting for dwell timeout"); return; }
    // touch events get blocked because mousemove gets triggered and creates a dwell element directly under the finger
    if(buttonTracker.triggerEvent && buttonTracker.triggerEvent.type == 'touchstart') { return; }
    var dwell_selection = buttonTracker.dwell_selection != 'button';
    // cursor-based trackers can throw the cursor up against the edges of the screen causing
    // inaccurate lingers for the buttons along the edges
    if(event.type == 'mousemove' && (event.clientX === 0 || event.clientY === 0 || event.clientX >= (window.innerWidth - 1) || event.clientY >= (window.innerHeight - 1))) {
      console.log("linger waiting because on a screen edge");
      return;
    }
    if(buttonTracker.last_triggering_dwell_event && dwell_selection) {
      // after a selection, require a little bit of movement before recognizing input
      var last = buttonTracker.last_triggering_dwell_event;
      var needed_distance = buttonTracker.check('dwell_release_distance') || 30;
      var diffX = Math.abs(event.clientX - last.clientX);
      var diffY = Math.abs(event.clientY - last.clientY);
      if(diffX < needed_distance && diffY < needed_distance) {
        console.log("linger waiting because selected recently");
        return;
      }
    } else if(buttonTracker.debounce) {
      // ignore linger events until the debounce has passed
      if(buttonTracker.last_selection && buttonTracker.last_selection.ts) {
        var now = (new Date()).getTime();
        if(now - buttonTracker.last_selection.ts < buttonTracker.debounce) {
          console.log("linger waiting because of debounce after selection");
          return;
        }
      }
    }
    buttonTracker.last_triggering_dwell_event = null;
    // - find the nearest selectable, with some liberal tolerance
    // - if we're already lingering
    //   - if we're outside the tolerance, start a new linger
    //   - otherwise average the linger's history and decide on the best candidate
    // - persist the current linger, record the starting timestamp
    // - if we've been lingering on the element for more than the cutoff, call element_release
    var elem_wrap = buttonTracker.find_selectable_under_event(event, true, false);
    if(elem_wrap && buttonTracker.dwell_ignore == elem_wrap.dom) {
      buttonTracker.dwell_ignore = null;
      console.log("linger waiting because on an ignore elem");
      return;
    }
    if(!buttonTracker.dwell_elem) {
      var elem = document.createElement('div');
      elem.id = 'linger';
      document.body.appendChild(elem);
      var spinner = document.createElement('div');
      spinner.className = 'spinner pie';
      elem.appendChild(spinner);
      var filler = document.createElement('div');
      filler.className = 'filler pie';
      elem.appendChild(filler);
      var mask = document.createElement('div');
      mask.className = 'mask';
      elem.appendChild(mask);
      buttonTracker.dwell_elem = elem;
      if(!dwell_selection) {
        buttonTracker.dwell_elem.classList.add('cursor');
      }
    }
    if(!buttonTracker.dwell_icon_elem) {
      var icon = document.createElement('div');
      icon.id = 'dwell_icon';
      icon.className = 'dwell_icon';
      document.body.appendChild(icon);
      buttonTracker.dwell_icon_elem = icon;
    }
    if(buttonTracker.check('dwell_cursor') || !dwell_selection) {
      buttonTracker.dwell_icon_elem.style.left = (event.clientX - 5) + "px";
      buttonTracker.dwell_icon_elem.style.top = (event.clientY - 5) + "px";
    }

    runCancel(buttonTracker.linger_clear_later);
    runCancel(buttonTracker.linger_close_enough_later);
    buttonTracker.dwell_timeout = buttonTracker.dwell_timeout || 1000;
    buttonTracker.dwell_animation = buttonTracker.dwell_animation || 'pie';
    var allowed_delay_between_events = Math.max(300, buttonTracker.dwell_timeout / 4);
    var minimum_interaction_window = 50;
    if(event.type == 'mousemove' && buttonTracker.dwell_no_cutoff) {
      allowed_delay_between_events = buttonTracker.dwell_timeout - minimum_interaction_window;
    }
    if(!buttonTracker.dwell_delay && buttonTracker.dwell_delay !== 0) {
      buttonTracker.dwell_delay = 100;
    }
    buttonTracker.linger_clear_later = runLater(function() {
      // clear the dwell icon if not dwell activity for a period of time
      console.log("linger cleared because linger timed out");
      buttonTracker.clear_dwell(elem_wrap && elem_wrap.dom);
    }, allowed_delay_between_events);

    var now = (new Date()).getTime();
    var duration = event.duration || 50;

    // Current target logic:
    // If already tracking, clear the current progress if
    //   - too long in total time
    //   - too long since a valid linger event
    //   - outside the tracked element's loose bounds
    // If we're still tracking
    //   - keep tracking if still on the same element
    //   - start over on a new element if lingering over a new element and
    //     still within the original tracked element's loosed bounds, but
    //     with more dwell gravity towards the new element
    //   - start over if on a new element
    if(buttonTracker.last_dwell_linger) {
      // check if we're outside the screen bounds, or the timestamp bounds.
      // if so clear the object
      if(now - buttonTracker.last_dwell_linger.started > buttonTracker.dwell_timeout + 1000 - duration) {
        // if it's been too long since starting to track the dwell, start over
        console.log("linger cleared because linger took too long");
        buttonTracker.last_dwell_linger = null;
      } else if(now - buttonTracker.last_dwell_linger.updated > allowed_delay_between_events - duration) {
        // if it's been too long since the last dwell event, start over
        console.log("linger cleared because too long a gap");
        buttonTracker.last_dwell_linger = null;
      } else {
        // if it's outside the loose bounds to the last target, start over
        var bounds = buttonTracker.last_dwell_linger.loose_bounds();
        if(event.clientX < bounds.left || event.clientX > bounds.left + bounds.width ||
              event.clientY < bounds.top || event.clientY > bounds.top + bounds.height) {
          console.log("linger cleared because out of bounds", event.clientX, event.clientY);
          buttonTracker.last_dwell_linger = null;
        }
      }
    }
    if(elem_wrap && buttonTracker.last_dwell_linger && elem_wrap.dom == buttonTracker.last_dwell_linger.dom) {
      // if still lingering on the same element, we're rockin'
      buttonTracker.buttonDown = true;
    } else if(dwell_selection && buttonTracker.dwell_gravity && elem_wrap && buttonTracker.last_dwell_linger && elem_wrap.dom != buttonTracker.last_dwell_linger.dom) {
      // if there's a valid existing linger for a different element, decide between it and the new linger
      var old_bounds = buttonTracker.last_dwell_linger.loose_bounds();
      var new_bounds = elem_wrap.loose_bounds();
      var avg_x = event.clientX * 3, avg_y = event.clientY * 3;
      var tally = 3;
      buttonTracker.last_dwell_linger.events.forEach(function(e, idx, list) {
        var weight = 1.0;
        // weight later events slightly more, otherwise it gets impossible to break out
        if(idx > (list.length / 2)) { weight = 2.0; }
        if(idx > (list.length * 2 / 3)) { weight = 3.0; }
        if(idx > (list.length * 4 / 5)) { weight = 5.0; }
        avg_x = avg_x + (e.clientX * weight);
        avg_y = avg_y + (e.clientY * weight);
        tally = tally + (1 * weight);
      });
      avg_x = avg_x / tally;
      avg_y = avg_y / tally;
      // cheap but less-accurate comparison
      var old_dist = (Math.abs(old_bounds.left + (old_bounds.width / 2) - avg_x) + Math.abs(old_bounds.top + (old_bounds.height / 2) - avg_y)) / 2;
      var new_dist = (Math.abs(new_bounds.left + (new_bounds.width / 2) - avg_x) + Math.abs(new_bounds.top + (new_bounds.height / 2) - avg_y)) / 2;
      if(new_dist < old_dist) {
        console.log("linger switched to new target", event.clientX, event.clientY, elem_wrap.dom);
        buttonTracker.last_dwell_linger = elem_wrap;
      }
    } else if(elem_wrap) {
      console.log("linger started for new target", event.clientX, event.clientY, elem_wrap.dom);
      buttonTracker.last_dwell_linger = elem_wrap;
    }

    if(buttonTracker.last_dwell_linger) {
      // place the dwell icon in the center of the current linger
      if(dwell_selection && !buttonTracker.last_dwell_linger.started) {
        // restart the excited doing-something animation
        buttonTracker.last_dwell_linger.started = now;
        var bounds = buttonTracker.last_dwell_linger.loose_bounds();
        buttonTracker.dwell_elem.style.left = (bounds.left + (bounds.width / 2) - 25) + "px";
        buttonTracker.dwell_elem.style.top = (bounds.top + (bounds.height / 2) - 25) + "px";
        // restart the animation
        var clone = buttonTracker.dwell_elem.cloneNode(true);
        clone.style.animationDuration = buttonTracker.dwell_timeout + 'ms';
        clone.style.webkitAnimationDuration = buttonTracker.dwell_timeout + 'ms';
        buttonTracker.dwell_elem.style.left = '-1000px';
        buttonTracker.dwell_elem.parentNode.replaceChild(clone, buttonTracker.dwell_elem);
        clone.classList.add('targeting');
        clone.classList.add(buttonTracker.dwell_animation);
        buttonTracker.dwell_elem = clone;
      }

      buttonTracker.last_dwell_linger.updated = now;
      buttonTracker.last_dwell_linger.events = buttonTracker.last_dwell_linger.events || [];
      buttonTracker.last_dwell_linger.events.push(event);
      if(dwell_selection) {
        // trigger selection if dwell has been for long enough
        if(now - buttonTracker.last_dwell_linger.started > buttonTracker.dwell_timeout) {
          event.dwell_linger = true;
          buttonTracker.element_release(buttonTracker.last_dwell_linger, event);
          buttonTracker.last_triggering_dwell_event = event;
          buttonTracker.last_dwell_linger = null;
          if(buttonTracker.dwell_delay) {
            buttonTracker.dwell_wait = true;
            runLater(function() {
              buttonTracker.dwell_wait = false;
            }, buttonTracker.dwell_delay);
          }
        } else {
          // if we're getting close to the dwell timeout, schedule a listener to trigger
          // it in case we don't get a follow-on event in time
          var will_trigger_at = buttonTracker.last_dwell_linger.started + buttonTracker.dwell_timeout;
          var ms_since_start = now - buttonTracker.last_dwell_linger.started;
          var ms_until_trigger = will_trigger_at - now;
          if((event.type == 'mousemove' && buttonTracker.dwell_no_cutoff && ms_since_start > minimum_interaction_window) || (ms_until_trigger < allowed_delay_between_events * 3 / 4)) {
            buttonTracker.linger_close_enough_later = runLater(function() {
              buttonTracker.dwell_linger(event);
            }, ms_until_trigger - 50);
          }
        }
      } else {
        buttonTracker.dwell_elem.classList.remove('targeting');
        buttonTracker.dwell_elem.style.left = (event.clientX - 25) + "px";
        buttonTracker.dwell_elem.style.top = (event.clientY - 25) + "px";
      }
    } else {
      // stick the dwell icon wherever it goes, with a sad nothing-here styling
      buttonTracker.dwell_elem.classList.remove('targeting');
      buttonTracker.dwell_elem.style.left = (event.clientX - 25) + "px";
      buttonTracker.dwell_elem.style.top = (event.clientY - 25) + "px";
    }
  },
  find_selectable_under_event: function(event, loose, allow_dwell) {
    event = buttonTracker.normalize_event(event);
    if(event.clientX === undefined || event.clientY === undefined) { return null; }
    var left = 0;
    var icon_left = 0;
    if(buttonTracker.dwell_elem) {
      var left = buttonTracker.dwell_elem.style.left;
      buttonTracker.dwell_elem.style.left = '-1000px';
    }
    if(buttonTracker.dwell_icon_elem) {
      var icon_left = buttonTracker.dwell_icon_elem.style.left;
      buttonTracker.dwell_icon_elem.style.left = '-1000px';
    }
    var $dropdown = $(".dropdown-backdrop")
    if($dropdown.length > 0) {
      $dropdown.hide();
    }
    var $target = $(document.elementFromPoint(event.clientX, event.clientY));
    if($dropdown.length > 0) {
      $dropdown.show();      
    }
    // If the identity dropdown is open and the user taps somewhere 
    // else on the screen, close the identity dropdown
    if($target.closest('#identity').length == 0 && $dropdown.length > 0) {
      if($target.closest('#identity ul').length == 0) {
        $target = $("#identity_button");
      }
    }
    if(buttonTracker.dwell_elem) {
      buttonTracker.dwell_elem.style.left = left;
    }
    if(buttonTracker.dwell_icon_elem) {
      buttonTracker.dwell_icon_elem.style.left = icon_left;
    }
    var region = $target.closest(".advanced_selection")[0];
    if(!region && loose) {
      // TODO: check the loose bounds of all the selectable elements, see if
      // you're close to anything selectable
    }
    if(region) {
      if(allow_dwell === false && $target.closest('.undwellable').length > 0) {
        return null;
      }
      if(region.id == 'pin') {
        return buttonTracker.element_wrap($target.closest("a")[0]);
      } else if(region.id == 'word_suggestions') {
        return buttonTracker.element_wrap($target.closest("a")[0]);
      } else if(region.id == 'identity') {
        if($target.closest('a').length > 0) {
          return buttonTracker.element_wrap($target.closest('a')[0]);
        } else {
          return buttonTracker.element_wrap($(region).find(".dropdown > a"));
        }
      } else if(region.id == 'sidebar_tease') {
        return buttonTracker.element_wrap(region);
      } else if(region.id == 'sidebar') {
        return buttonTracker.element_wrap($target.closest(".btn,a")[0]);
      } else if(region.id == 'speak_menu') {
        return buttonTracker.element_wrap($target.closest("a")[0]);
      } else if(region.tagName == 'HEADER') {
        var $elem = $target.closest(".btn:not(.pass_through),#button_list")
        if($elem.hasClass('pass_to_btn_list') && allow_dwell === false) {
          $elem = $("#button_list");
        }
        return buttonTracker.element_wrap($elem[0]);
      } else if((region.className || "").match(/board/) || region.id == 'board_canvas') {
        return buttonTracker.button_from_point(event.clientX, event.clientY);
      } else if(region.id == 'integration_overlay') {
        return buttonTracker.element_wrap($target.closest(".integration_target")[0]);
      }
    }
    return null;
  },
  button_from_point: function(x, y) {
    // TODO: support virtual board dom
    var elem_left = null;
    var icon_left = null;
    if(buttonTracker.dwell_elem) {
      elem_left = buttonTracker.dwell_elem.style.left;
      buttonTracker.dwell_elem.style.left = '-1000px';
    }
    if(buttonTracker.dwell_icon_elem) {
      icon_left = buttonTracker.dwell_icon_elem.style.left;
      buttonTracker.dwell_icon_elem.style.left = '-1000px';
    }
    var elem = document.elementFromPoint(x, y);
    if(buttonTracker.dwell_elem) {
      buttonTracker.dwell_elem.style.left = elem_left;
    }
    if(buttonTracker.dwell_icon_elem) {
      buttonTracker.dwell_icon_elem.style.left = icon_left;
    }

    var $target = $(elem).closest('.button');
    // If the target is hidden, but the empty grid is showing (not a hint,
    // and not Show Hidden Buttons)
    if($target.hasClass('hidden_button')) {
      if($target.closest('.board.show_all_buttons').length == 0) {
        if($target.closest('.board.speak.grid_hidden_buttons').length > 0) {
          $target = $target.filter("none");
        }
      }
    }
    if($target.length > 0) {
      return buttonTracker.element_wrap($target[0]);
    } else if(app_state.get('speak_mode')) {
      // used for finding via the virtual dom
      var $board = $(".board");
      if($board.length === 0) { return null; }
      var offset = $board.offset() || {};
      var top = offset.top;
      if(top) {
        var button = app_state.get('board_virtual_dom').button_from_point(x, y - top - 3);
        return buttonTracker.element_wrap(button);
      }
    }
  },
  element_wrap: function(elem) {
    if(!elem) { return null; }
    var res = null;
    var loose_distance = 5;
    if(buttonTracker.dwell_gravity) {
      loose_distance = 50;
    }
    if(elem.button) {
      res = {
        id: elem.id,
        dom: elem.id,
        index: elem.index,
        virtual_button: true,
        addClass: function(str) {
          app_state.get('board_virtual_dom').add_state(str, elem.id);
        },
        trigger: function(event) {
          app_state.get('board_virtual_dom').trigger(event, elem.id);
        },
        trigger_special: function(event, args) {
          app_state.get('board_virtual_dom').trigger(event, elem.id, args);
        },
        loose_bounds: function() {
          return {
            width: elem.width + (loose_distance * 2),
            height: elem.height + (loose_distance * 2),
            top: elem.top - loose_distance,
            left: elem.left - loose_distance
          };
        },
        data: function(attr, val) {
          if(arguments.length == 2) {
            emberSet(elem, attr, val);
          } else {
            return emberGet(elem, attr);
          }
        }
      };
    } else {
      var $e = $(elem);
      res = {
        id: $e.attr('data-id'),
        dom: elem,
        addClass: function(str) {
          $e.addClass(str);
        },
        trigger: function(event) {
          $e.trigger(event);
        },
        trigger_special: function(event, args) {
          var e = $.Event( event );
          for(var idx in args) {
            e[idx] = args[idx];
          }
          $e.trigger(e);
        },
        loose_bounds: function() {
          if(res.cached_loose_bounds) { return res.cached_loose_bounds; }
          var offset = {};
          if($e.length > 0) { offset = $e.offset() || {}; }
          res.cached_loose_bounds = {
            width: $e.outerWidth() + (loose_distance * 2),
            height: $e.outerHeight() + (loose_distance * 2),
            top: offset.top - loose_distance,
            left: offset.left - loose_distance
          };
          return res.cached_loose_bounds;
        },
        data: function(attr, val) {
          return $e.data(attr, val);
        }
      };
    }
    return res;
  },
  find_button_under_event: function(event, no_side_effects) {
    if(buttonTracker.drag) {
      buttonTracker.drag.hide();
    }
    // TODO: Don't just use the pointer location, use the middle of the button...
    // right now if you grab an edge and drag it feels weird when most of your button is over a
    // different button but it's not switching because your cursor hasn't gotten there yet.
    var x = event.clientX + (this.measureAdjustX || 0);
    var y = event.clientY + (this.measureAdjustY || 0);
    var result_wrap = buttonTracker.button_from_point(x, y);
    if(buttonTracker.drag && result_wrap && result_wrap.dom == buttonTracker.drag.data('overClone')) {
      result_wrap = buttonTracker.element_wrap(buttonTracker.drag.data('elem'));
    }
    if(!no_side_effects) {
      if(buttonTracker.drag) {
        buttonTracker.drag.show();
      }
    }
    return result_wrap;
  },
  locate_button_on_board: function(id, event) {
    var x = null, y = null;
    if(event && event.clientX !== undefined && event.clientY !== undefined) {
      x = event.clientX;
      y = event.clientY;
    } else {
      // TODO: support virtual board dom
      var $button = $(".button[data-id='" + id + "']");
      if($button[0]) {
        var offset = $button.offset();
        x = offset.left + ($button.outerWidth() / 2);
        y = offset.top + ($button.outerHeight() / 2);
      } else {
        var button = app_state.get('board_virtual_dom').button_from_id(id);
        if(button) {
          x = button.left + (button.width / 2);
          y = button.top + (button.height / 2);
        }
      }
    }
    if(x && y) {
      var $board = $(".board");
      if($board.length) {
        var left = $board.offset().left;
        var top = $board.offset().top;
        var $sidebar = $("#sidebar");
        var sidebar_width = 0;
        if($sidebar.length > 0) {
          sidebar_width = $sidebar.outerWidth() || 0;
        }
        var width = $board.width() + left + sidebar_width;
        var height = $board.height() + top;
        var pct_x = (x - left) / width;
        var pct_y = (y - top) / height;
        return {percent_x: pct_x, percent_y: pct_y};
      }
    }
    return null;
  },
  track_drag: function(event) {
    this.startEvent = this.startEvent || event;
    var diffX = event.pageX - this.startEvent.pageX;
    var diffY = event.pageY - this.startEvent.pageY;
    var elem_wrap = null;

    if(Math.abs(event.pageX - this.startEvent.pageX) < this.drag_distance && Math.abs(event.pageY - this.startEvent.pageY) < this.drag_distance) {
      return;
    } else if(this.ignored_region(this.startEvent)) {
      return;
    }
    if(!buttonTracker.drag) {
      elem_wrap = this.find_button_under_event(this.startEvent);
      if(elem_wrap && elem_wrap.dom && app_state.get('edit_mode')) {
        var $elem = $(elem_wrap.dom);
        this.start_dragging($elem, this.startEvent);
        $elem.css('opacity', 0.0);
      }
    } else {
      elem_wrap = this.find_button_under_event(event);
    }
    return elem_wrap;
  },
  clear_dwell: function(elem) {
    if(buttonTracker.dwell_elem) {
      if(elem) {
        buttonTracker.dwell_ignore = elem;
        runLater(function() {
          if(buttonTracker.dwell_ignore == elem) {
            buttonTracker.dwell_ignore = null;
          }
        }, 500);
      }

      buttonTracker.dwell_elem.parentNode.removeChild(buttonTracker.dwell_elem);
      buttonTracker.dwell_elem = document.getElementById('linger');
      buttonTracker.dwell_icon_elem.parentNode.removeChild(buttonTracker.dwell_icon_elem);
      buttonTracker.dwell_icon_elem = document.getElementById('dwell_icon');
      if(buttonTracker.check('dwell_selection') == 'button') {
        if(buttonTracker.last_dwell_linger && buttonTracker.last_dwell_linger.events && buttonTracker.last_dwell_linger.events.length) {
          var events = buttonTracker.last_dwell_linger.events;
          buttonTracker.last_dwell_linger.events = [events[events.length - 1]];
        }
      } else {
        buttonTracker.last_dwell_linger = null;
      }
    }
    if(buttonTracker.dwell_icon_elem) {
      buttonTracker.dwell_icon_elem.style.left = '-1000px';
    }
  },
  start_dragging: function($elem, event) {
    // create drag element
    var width = $elem.outerWidth();
    var height = $elem.height();
    buttonTracker.drag = $elem.clone().addClass('clone');
    buttonTracker.drag.css({width: width, height: height, zIndex: 2});
    // buttonTracker.drag.find('.button').css('background', '#fff');
    buttonTracker.drag.data('elem', $elem[0]);
    $('body').append(buttonTracker.drag);

    editManager.set_drag_mode(true);
    var offset = $elem.offset();
    this.initialButtonX = offset.left;
    this.initialButtonY = offset.top;
    this.buttonAdjustX = this.initialButtonX - event.pageX;
    this.buttonAdjustY = this.initialButtonY - event.pageY;
    this.measureAdjustX = (this.initialButtonX + (width / 2)) - event.pageX;
    this.measureAdjustY = (this.initialButtonY + (height / 2)) - event.pageY;
  },
  stop_dragging: function() {
    editManager.set_drag_mode(false);
    this.startEvent = null;
    this.initialButtonX = 0;
    this.initialButtonY = 0;
    this.buttonAdjustX = 0;
    this.buttonAdjustY = 0;
    this.measureAdjustX = 0;
    this.measureAdjustY = 0;
    this.set('buttons', []);
    this.longPressEvent = null;
  },
  normalize_event: function(event) {
    if(event.originalEvent && event.originalEvent.touches && event.originalEvent.touches[0]) {
      event.pageX = event.originalEvent.touches[0].pageX;
      event.pageY = event.originalEvent.touches[0].pageY;
      event.clientX = event.originalEvent.touches[0].clientX;
      event.clientY = event.originalEvent.touches[0].clientY;
      event.total_touches = event.originalEvent.touches.length;
    }
    if(event.originalEvent && event.originalEvent.changedTouches && event.originalEvent.changedTouches[0]) {
      event.pageX = event.originalEvent.changedTouches[0].pageX;
      event.pageY = event.originalEvent.changedTouches[0].pageY;
      event.clientX = event.originalEvent.changedTouches[0].clientX;
      event.clientY = event.originalEvent.changedTouches[0].clientY;
      event.total_touches = event.originalEvent.touches.length;
    }
    return event;
  },
  ignored_region: function(event) {
    var target = event && event.target;
    var result = !!(target && (
                      target.tagName == 'INPUT' ||
//                      target.className == 'dropdown-backdrop' ||
                      target.className == 'modal' ||
                      target.className == 'modal-dialog'
                    ));
    return result;
  },
  long_press_delay: 2500,
  track_long_press: function() {
    if(this.longPressEvent) {
      var button_wrap = this.find_button_under_event(this.longPressEvent);
      if(button_wrap) {
        this.ignoreUp = true;
        editManager.start_edit_mode();
      }
    }
  },
  track_short_press: function() {
    if(this.longPressEvent) {
      var selectable_wrap = this.find_selectable_under_event(this.longPressEvent, true);
      if(selectable_wrap) {
        var target = this.longPressEvent.originalTarget || (this.longPressEvent.originalEvent || this.longPressEvent).target
        var event = $.Event('touchend', target);
        event.clientX = this.longPressEvent.clientX;
        event.clientY = this.longPressEvent.clientY;
        buttonTracker.element_release(selectable_wrap, event);
        this.ignoreUp = true;
      }
    }
  },
  track_selection: function(opts) {
    if(buttonTracker.last_selection && buttonTracker.last_selection.ts) {
      var now = (new Date()).getTime();
      if(buttonTracker.debounce && now - buttonTracker.last_selection.ts < buttonTracker.debounce) {
        return { proceed: false, debounced: true};
      }
    }
    var ls = {
      event_type: opts.event_type,
      selection_type: opts.selection_type,
      total_events: opts.total_events || 1,
      multi_touch_events: opts.multi_touch_events || 0,
      ts: (new Date()).getTime()
    };
    if(ls.selection_type == 'touch' && ls.total_events > 0 && ls.multi_touch_events > 0 && (ls.multi_touch_events / (ls.total_events - 1)) >= 0.4) {
      ls.multi_touch = true;
    }
    if(ls.multi_touch && buttonTracker.check('multi_touch_modeling')) {
      ls.modeling = true;
    } else if(ls.selection_type != 'dwell' && buttonTracker.check('dwell_modeling')) {
      ls.modeling = true;
    }
    stashes.last_selection = ls;
    buttonTracker.last_selection = ls;
    return { proceed: true };
  },
  frame_event: function(event, event_type) {
    if(!event || event.triggered_for == event_type) {
      return;
    }
    var raw_event_type = event.type;
    // TODO: once aac_shim is updated, this manual change should be unnecessary
    if(event_type == 'select' && (event.type == 'mouseup' || event.type == 'mousedown' || event.type == 'touchstart' || event.type == 'touchend')) {
      raw_event_type = 'click';
    }
    event.triggered_for = event_type;
    if($(event.target).closest("#integration_overlay").length > 0) {
      event.preventDefault();
      frame_listener.raw_event({
        type: raw_event_type,
        aac_type: event_type,
        clientX: event.clientX,
        clientY: event.clientY
      });
    }
  },
  focus_tab: function(from_start) {
    if(!buttonTracker.focus_wrap) {
      var b = app_state.get('board_virtual_dom').button_from_index(from_start ? 0 : -2);
      buttonTracker.focus_wrap = buttonTracker.element_wrap(b);
    }
    buttonTracker.focus_wrap.addClass('touched');
    // set focus for the current button, set current button to zero if none set
    // if shift_key is held down then we're coming in backwards, which is important to know
  },
  select_tab: function() {
    // trigger buttonselect for the current button
    buttonTracker.focus_wrap.trigger('buttonselect');
  },
  move_tab: function(forward) {
    // progress forward or backward to the adjacent button
    // return true if there is an adjacent button, if not then
    // clear the tab and return false
    if(buttonTracker.focus_wrap) {
      var b = app_state.get('board_virtual_dom').button_from_index(buttonTracker.focus_wrap.index + (forward ? 1 : -1));
      buttonTracker.focus_wrap = buttonTracker.element_wrap(b);
    }
    if(buttonTracker.focus_wrap) {
      buttonTracker.focus_wrap.addClass('touched');
    } else {
      buttonTracker.clear_tab();
    }
    return !!buttonTracker.focus_wrap;
  },
  clear_tab: function() {
    app_state.get('board_virtual_dom').clear_touched();
    buttonTracker.focus_wrap = null;
    // remove the current button state
  },
  drag_distance: 20,
  buttons: []
}).create();

window.addEventListener('gamepadconnected', function(e) {
  buttonTracker.gamepads = buttonTracker.gamepads || {};
  var pad = e.gamepad;
  var buttons = [];
  if(pad.buttons) {
    for(var idx = 0; idx < pad.buttons.length; idx++) {
      if(pad.buttons[idx].value !== undefined) {
        buttons.push(pad.buttons[idx].value);
      } else {
        buttons.push(pad.buttons[idx].pressed ? 1.0 : 0.0);
      }
      buttons.push(pad.buttons[idx]);
    }
  }
  var axes = [];
  if(pad.axes) {
    for(var idx = 0; idx < pad.axes.length; idx++) {
      axes.push(pad.axes[idx]);
    }
  }
  buttonTracker.gamepads[e.gamepad.id] = pad;
  buttonTracker.direction_event('gamepads');
});
window.addEventListener('gamepaddisconnected', function(e) {
  buttonTracker.gamepads = buttonTracker.gamepads || {};
  delete buttonTracker.gamepads[e.gamepad.id];
});
if (!('ongamepadconnected' in window)) {
  // No gamepad events available, poll instead.
  buttonTracker.gamepad_check_interval = setInterval(function() {
    if(app_state.get('speak_mode') && buttonTracker.check('dwell_type')) {
      buttonTracker.update_gamepads();
      if(Object.keys(buttonTracker.gamepads).length > 0) {
        buttonTracker.direction_event('gamepads');
      }
    }
  }, 10000);
}


window.buttons = buttonTracker;

export default buttonTracker;
