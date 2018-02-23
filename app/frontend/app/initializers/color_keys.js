import Ember from 'ember';
import app_state from '../utils/app_state';
import { htmlSafe } from '@ember/string';

export default {
  name: 'color_keys',
  initialize: function() {
    window.CoughDrop.keyed_colors.forEach(function(r) {
      if(!r.border) {
        var fill = window.tinycolor(r.fill);
        var border = fill.darken(30);
        r.border = border.toHexString();
      }
      r.style = htmlSafe("border-color: " + r.border + "; background: " + r.fill + ";");
    });
    app_state.set('colored_keys', true);
  }
};
