import Ember from 'ember';
import buttonTracker from '../utils/raw_events';
import app_state from '../utils/app_state';
import editManager from '../utils/edit_manager';
import capabilities from '../utils/capabilities';

export default Ember.Component.extend({
  didInsertElement: function() {
    this.redraw();
  },
  redraw: function() {
    var button = this.get('button');
    var $canvas = Ember.$(this.element).find("canvas");
    var _this = this;
    if($canvas[0]) {
      $canvas.attr('width', 500);
      $canvas.attr('height', 500);
      var context = $canvas[0].getContext('2d');
      var width = 500;
      var height = 500;
      var radius = 50;
      var pad = 20;
      context.save();
      context.clearRect(0, 0, width, height);
      context.beginPath();
      context.moveTo(pad + radius, pad);
      context.lineTo(width - pad - radius, pad);
      context.arcTo(width - pad, pad, width - pad, pad + radius, radius);
      context.lineTo(width - pad, height - pad - radius);
      context.arcTo(width - pad, height - pad, width - pad - radius, height - pad, radius);
      context.lineTo(pad + radius, height - pad);
      context.arcTo(pad, height - pad, pad, height - pad - radius, radius);
      context.lineTo(pad, pad + radius);
      context.arcTo(pad, pad, pad + radius, pad, radius);
      context.lineWidth = 25;
      context.fillStyle = button.background_color || '#fff';
      context.strokeStyle = button.border_color || '#ddd';
      context.stroke();
      context.fill();

      context.textAlign = 'center';
      var size = 80;
      context.font = size + 'px Arial';
      while(size > 40 && context.measureText(button.label || '').width > 470) {
        size = size - 5;
        context.font = size + 'px Arial';
      }
      context.fillStyle = '#000';
      context.save();
      context.rect(pad, 0, width - pad - pad - context.lineWidth, height);
      context.clip();
      if(size <= 40 && context.measureText(button.label || '').width > 470) {
        var words = button.label.split(/\s/);
        var top = [];
        while(top.join(' ').length < button.label.length / 2) {
          top.push(words.shift());
        }
        context.fillText(top.join(' '), width / 2, pad + (pad / 3) + size);
        context.fillText(words.join(' '), width / 2, pad + (pad / 3) + size + size);
      } else {
        context.fillText(button.label, width / 2, pad + size);
      }
      context.restore();
      context.save();
      context.rect(pad + pad, pad + pad, width - pad - pad, height - pad - pad);
      context.clip();
      if(Ember.get(button, 'local_image_url') || Ember.get(button, 'image_url') || Ember.get(button, 'image.url') || Ember.get(button, 'image')) {
        var img = new Image();
        img.src = Ember.get(button, 'local_image_url') || Ember.get(button, 'image_url') || Ember.get(button, 'image.url') || Ember.get(button, 'image');
        img.onload = function() {
          if(_this.get('button.id') == button.id) {
            context.drawImage(img, 75, 125, 350, 350);
          }
        };
      }
      context.restore();
      context.restore();
    }
  }.observes('button.id')
});
