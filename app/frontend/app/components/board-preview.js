import Ember from 'ember';
import Component from '@ember/component';
import CoughDrop from '../app';
import modal from '../utils/modal';
import app_state from '../utils/app_state';
import persistence from '../utils/persistence';

export default Component.extend({
  willInsertElement: function() {
    this.set('include_canvas', window.outerWidth > 800);
    this.set('model', {loading: true});
    var _this = this;
    if(_this.get('key')) {
      CoughDrop.store.findRecord('board', _this.get('key')).then(function(board) {
        if(!board.get('permissions')) {
          board.reload(false).then(function(board) {
            _this.set('model', board);
          });
        } else {
          _this.set('model', board);
        }
      }, function(err) {
        _this.set('model', {error: true});
      });
    }
  },
  select_option: function() {
    return this.get('option') == 'select';
  }.property('option'),
  render_canvas: function() {
    if(this.get('model.id')) {
      var canvas = this.element.getElementsByTagName('canvas')[0];
      var board = this.get('model');
      if(canvas) {
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
        var border_size = pad / 2.5;
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
            if(button_id && buttons[button_id]) {
              var button = buttons[button_id];
              if(!button.hidden) {
                var x = button_width * jdx;
                var y = button_height * idx;
                var draw_button = function(button, x, y, fill) {
                  context.beginPath();
                  context.strokeStyle = button.border_color || "#CCC";
                  context.fillStyle = button.background_color || "#FFF";
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
                  if(button.load_board || button.url || button.apps || button.integration) {
                    context.beginPath();
                    context.arc(x + button_width - pad, y + pad, button_width / 8, 0, 2*Math.PI);
                    context.fillStyle = context.strokeStyle;
                    context.fill();
                  }
                  if(button.label) {
                    context.fillStyle = '#000';
                    context.fillText(button.label, x + (button_width / 2), y + pad + (text_height * 0.85));
                  }
                  context.restore();
                };
                draw_button(button, x, y, true);

                if(button.image_id && board.get('image_urls')[button.image_id]) {
                  var url = board.get('image_urls')[button.image_id];
                  (function(button, x, y, url) {
                    var draw = function(url) {
                      var img = new Image();
                      var button_ratio = image_width / image_height;
                      img.onload = function() {
                        var image_ratio = img.width / img.height;
                        var width = image_width;
                        var height = image_height;
                        var image_x = x + border_size + pad;
                        var image_y = y + border_size + pad + text_height;
                        if(image_ratio > button_ratio) {
                          // wider than the space
                          var diff = (1 - (button_ratio / image_ratio)) * height;
                          image_y += diff / 2;
                          height -= diff;
                        } else if(image_ratio < button_ratio) {
                          // taller than the space
                          var diff = (1 - (image_ratio / button_ratio)) * width;
                          image_x += diff / 2;
                          width -= diff;
                        }
                        context.drawImage(img, image_x, image_y, width, height);
                      };
                      img.src = url;
                    };
                    persistence.find_url(url).then(function(url) {
                      draw(url);
                    }, function() {
                      draw(url);
                    });
                  })(button, x, y, url);
                }
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
    }
  }.observes('model.id'),
  actions: {
    select: function() {
      this.sendAction();
    },
    close: function() {
      modal.close_board_preview();
    },
    visit: function() {
      app_state.controller.transitionToRoute('board', this.get('model.key'));
    }
  }
});
