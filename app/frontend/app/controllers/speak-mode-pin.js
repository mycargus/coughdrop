import modal from '../utils/modal';
import app_state from '../utils/app_state';

export default modal.ModalController.extend({
  pin: "",
  compare_pin: function() {
    var pin = this.get('pin');
    if(pin == this.get('model.actual_pin')) {
      this.set('pin', '');
      modal.close({correct_pin: true});
      if(this.get('model.action') == 'none') { return; }
      app_state.toggle_speak_mode('off');
      if(this.get('model.action') == 'edit') {
        app_state.toggle_edit_mode();
      }
    } else if(pin && pin.length >= 4) {
      // error message
      this.set('invalid_pin', true);
      this.set('pin', '');
    }
  }.observes('pin'),
  opening: function() {
    this.set('pin', '');
  },
  update_pin: function() {
    var str = this.get('pin_dots') || "";
    var pin = this.get('pin');
    for(var idx = 0; idx < str.length; idx++) {
      if(str[idx] != "●") {
        pin = pin + str[idx];
      }
    }
    if(pin != this.get('pin')) {
      this.set('pin', pin);
    }
  }.observes('pin_dots'),
  update_pin_dots: function() {
    var str = "●";
    var res = "";
    var steps = (this.get('pin') || '').length;
    for(var idx = 0; idx < steps; idx++) {
      res = res + str;
    }
    if(res != this.get('pin_dots')) {
      this.set('pin_dots', res);
    }
  }.observes('pin'),
  actions: {
    add_digit: function(digit) {
      var pin = this.get('pin') || "";
      pin = pin + digit.toString();
      this.set('pin', pin);
    },
    reveal_pin: function() {
      this.set('show_pin', true);
    }
  }
});