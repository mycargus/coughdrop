import Ember from 'ember';
import Component from '@ember/component';
import { later as runLater } from '@ember/runloop';

export default Component.extend({
  willInsertElement: function() {
    if(!this.get('already_opened')) {
      var _this = this;
      runLater(function() {
        // TODO: this is considered bad behavior. an error was being triggered after upgrading
        // because we're setting an attribute before the rendering has finished
        _this.set('already_opened', true);
        _this.sendAction('opening');
      });
    }
  },
  didInsertElement: function() {
    if(!this.get('already_done_opening')) {
      this.set('already_done_opening', true);
      this.sendAction('done_opening');
    }
  },
  willDestroy: function() {
    if(!this.get('already_closed')) {
      this.set('already_closed', true);
      this.sendAction('closing');
    }
  }
});



