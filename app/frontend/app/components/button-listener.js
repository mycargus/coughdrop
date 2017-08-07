import Ember from 'ember';
import buttonTracker from '../utils/raw_events';
import app_state from '../utils/app_state';
import editManager from '../utils/edit_manager';
import capabilities from '../utils/capabilities';

var board_ids = {};
export default Ember.Component.extend({
  didInsertElement: function() {
    var _this = this;
    Ember.$(window).on('resize orientationchange', function() {
      Ember.run.later(function() {
        // on mobile devices, keyboard popup shouldn't trigger a redraw
        if(app_state.get('window_inner_width') && capabilities.mobile && window.innerWidth == app_state.get('window_inner_width')) {
          // TODO: do we need to force scrolltop to 0?
          return;
        }
        _this.sendAction('compute_height', true);
      }, 100);
    });
    _this.sendAction('compute_height');
  },
  buttonId: function(event) {
    var $button = Ember.$(event.target).closest('.button');
    return $button.attr('data-id');
  },
  buttonSelect: function(event) {
    if(app_state.get('feature_flags.super_fast_html')) {
      var board_id = app_state.get('currentBoardState.id');
      var content = document.getElementsByClassName('board')[0];
      if(Object.keys(board_ids).length > 1 && content) {
        var keys = Object.keys(board_ids);
        if(board_ids.current_id == keys[0]) {
          content.innerHTML = board_ids[keys[1]];
          board_ids.current_id = keys[1];
        } else {
          content.innerHTML = board_ids[keys[0]];
          board_ids.current_id = keys[0];
        }
        return;
      }
      if(!board_ids[board_id]) {
        if(content) {
          board_ids[board_id] = content.innerHTML;
        }
      }
    }
    var button_id = this.buttonId(event);
    if(app_state.get('edit_mode') && editManager.paint_mode) {
      this.buttonPaint(event);
    } else {
      this.sendAction('button_event', 'buttonSelect', button_id, event);
    }
  },
  buttonPaint: function(event) {
    if(editManager.paint_mode) {
      var button_id = this.buttonId(event);
      this.sendAction('button_event', 'buttonPaint', button_id);
    }
  },
  symbolSelect: function(event) {
    if(app_state.get('edit_mode')) {
      if(editManager.finding_target()) {
        return this.buttonSelect(event);
      }
      var button_id = this.buttonId(event);
      this.sendAction('button_event', 'symbolSelect', button_id);
    }
  },
  actionSelect: function(event) {
    if(app_state.get('edit_mode')) {
      if(editManager.finding_target()) {
        return this.buttonSelect(event);
      }
      var button_id = this.buttonId(event);
      this.sendAction('button_event', 'actionSelect', button_id);
    }
  },
  rearrange: function(event) {
    if(app_state.get('edit_mode')) {
      var dragId = Ember.$(event.target).data('drag_id');
      var dropId = Ember.$(event.target).data('drop_id');
      this.sendAction('button_event', 'rearrangeButtons', dragId, dropId);
    }
  },
  clear: function(event) {
    if(app_state.get('edit_mode')) {
      var button_id = this.buttonId(event);
      this.sendAction('button_event', 'clear_button', button_id);
    }
  },
  stash: function(event) {
    if(app_state.get('edit_mode')) {
      var button_id = this.buttonId(event);
      this.sendAction('button_event', 'stash_button', button_id);
    }
  }
});
