import Ember from 'ember';
import Component from '@ember/component';
import $ from 'jquery';
import contentGrabbers from '../utils/content_grabbers';
import app_state from '../utils/app_state';
import word_suggestions from '../utils/word_suggestions';
import Utils from '../utils/misc';
import modal from '../utils/modal';
import i18n from '../utils/i18n';
import CoughDrop from '../app';

export default Component.extend({
  willInsertElement: function() {
    this.load_boards();
    this.set('current_index', null);
    this.set('prompt', true);
    this.set('level_select', null);
  },
  didInsertElement: function() {
    var window_height = window.innerHeight;
    var elem = this.element;
    var rect = elem.getBoundingClientRect();
    var top = rect.top;
    this.set('height', (window_height - top));
    elem.style.height = this.get('height') + "px";
  },
  update_current_board: function() {
    if(this.get('current_index') == undefined && this.get('sorted_boards.length')) {
      var _this = this;
      var index = 0;
      this.get('sorted_boards').forEach(function(b, idx) {
        if(b.get('grid.rows') * b.get('grid.columns') > 30 && index === 0) {
          index = idx;
        } else if(index == 0 && idx == _this.get('sorted_boards').length - 1) {
          index = idx;
        }
      });
      _this.set('current_index', index);
    }
    this.set('current_board', this.get('sorted_boards')[this.get('current_index')]);
  }.observes('sorted_boards', 'current_index'),
  draw_current_board: function() {
    var canvas = this.element.getElementsByTagName('canvas')[0];
    var board = this.get('current_board');
    var show_all = true;
    var show_links = false;
    if(canvas && board) {
      canvas.style.display = 'inline';
      var context = canvas.getContext('2d');
      var rect = canvas.getBoundingClientRect();

      var width = rect.width * 2;
      canvas.setAttribute('width', width);
      var height = rect.height * 2;
      canvas.setAttribute('height', height);
      var pad = width / 120;

      context.save();
      context.clearRect(0, 0, width, height);

      var rows = board.get('grid.rows');
      var columns = board.get('grid.columns');
      var buttons = {};
      (board.get('buttons') || []).forEach(function(button) {
        buttons[button.id] = button;
      });
      var button_width = width / columns;
      var button_height = height / rows;
      var radius = button_width / 20;
      var border_size = pad / 4;
      if(rows > 4 || columns > 8) {
        pad = pad / 2;
      }
      var inner_height = (button_height - pad - pad - border_size - border_size);
      var text_height = inner_height * 0.25;
      text_height = Math.min(text_height, height / 20);
      var image_height = inner_height - text_height;
      var image_width = button_width - pad - pad - border_size - border_size;
      context.font = text_height + "px Arial";
      context.textAlign = 'center';
      var handle_button = function(button_id) {
          if((button_id && buttons[button_id]) || show_all) {
            var button = buttons[button_id] || {};
            if(!button.hidden || show_all) {
              var x = button_width * jdx;
              var y = button_height * idx;
              var draw_button = function(button, x, y, fill) {
                context.beginPath();
                context.strokeStyle = "#aaa";
                context.fillStyle = "#eee";
                context.lineWidth = border_size;

                context.moveTo(x + pad + radius, y + pad);
                context.lineTo(x + button_width - pad - radius, y + pad);
                context.arcTo(x + button_width - pad, y + pad, x + button_width - pad, y + pad + radius, radius);
                context.lineTo(x + button_width - pad, y + pad + radius, x + button_width - pad, y + button_height - pad - radius);
                context.arcTo(x + button_width - pad, y + button_height - pad, x + button_width - pad - radius, y + button_height - pad, radius);
                context.lineTo(x + pad + radius, y + button_height - pad);
                context.arcTo(x + pad, y + button_height - pad, x + pad, y + button_height - pad - radius, radius);
                context.lineTo(x + pad, y + pad + radius);
                context.arcTo(x + pad, y + pad, x + pad + radius, y + pad, radius);

                if(fill) {
                  context.fill();
                }
                context.stroke();
                context.save();
                context.clip();
                if(show_links && button && (button.load_board || button.url || button.apps || button.integration)) {
                  context.beginPath();
                  context.arc(x + button_width - pad, y + pad, button_width / 8, 0, 2*Math.PI);
                  context.fillStyle = context.strokeStyle;
                  context.fill();
                }
                context.restore();
              };
              draw_button(button, x, y, true);
            }
          }
      };
      for(var idx = 0; idx < rows; idx++) {
        for(var jdx = 0; jdx < columns; jdx++) {
          var button_id = ((board.get('grid.order') || [])[idx] || [])[jdx];
          handle_button(button_id);
        }
      }
    }
  }.observes('current_board'),
  update_sorted_boards: function() {
    var res = (this.get('boards') || []).sort(function(a, b) {
      var a_size = a.get('grid.rows') * a.get('grid.columns');
      var b_size = b.get('grid.rows') * b.get('grid.columns');
      if(a_size == b_size) {
        return a.get('grid.columns') - b.get('grid.columns');
      } else {
        return a_size - b_size;
      }
    });
    this.set('sorted_boards', res);
  }.observes('boards'),
  load_boards: function() {
    var _this = this;
    _this.set('status', {loading: true});
    _this.set('boards', null);
    var canvas = _this.element.getElementsByTagName('canvas')[0];
    if(canvas) { canvas.style.display = 'none'; }
    CoughDrop.store.query('board', {public: true, starred: true, user_id: 'example', per_page: 6, category: 'layout'}).then(function(data) {
      var res = data.map(function(b) { return b; });
      if(res && res.length > 0) {
        _this.set('boards', res);
        _this.set('status', null);
      } else {
        _this.set('status', {error: true});
        _this.sendAction('load_error');
      }
    }, function(err) {
      _this.set('status', {error: true});
      _this.sendAction('load_error');
    });
  },
  no_next: function() {
    return !(this.get('current_index') < (this.get('sorted_boards.length') - 1) && this.get('sorted_boards.length') > 0);
  }.property('current_index', 'sorted_boards'),
  no_previous: function() {
    return !(this.get('current_index') > 0 && this.get('sorted_boards.length') > 0);
  }.property('current_index', 'sorted_boards'),
  actions: {
    next: function() {
      this.set('current_index', Math.min((this.get('current_index') || 0) + 1, (this.get('sorted_boards.length') || 1) - 1));
    },
    previous: function() {
      this.set('current_index', Math.max((this.get('current_index') || 0) - 1, 0));
    },
    advanced: function() {
      this.sendAction('advanced');
    },
    select: function() {
      var _this = this;
      var user = app_state.get('currentUser');
      var board = _this.get('current_board');
      if(true || _this.get('current_level') || !board.get('levels')) {
        if(_this.get('current_board.key')) {
          user.copy_home_board(_this.get('current_board')).then(function() { }, function(err) {
            modal.error(i18n.t('set_as_home_failed', "Home board update failed unexpectedly"));
          });
        }
        _this.sendAction('select', _this.get('current_board'));  
      } else {
        _this.set('level_select', true);
      }
    },
    dismiss: function() {
      this.set('prompt', null);
    }
  }
});
