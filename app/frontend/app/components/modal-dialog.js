import Ember from 'ember';
import capabilities from '../utils/capabilities';

export default Ember.Component.extend({
  didInsertElement: function() {
    this.stretch();
    if(!this.get('already_opened')) {
      this.set('already_opened', true);
      this.sendAction('opening');
    }
//     if(capabilities.mobile) {
      var height = Ember.$(window).height() - 50;
      Ember.$(this.get('element')).find(".modal-content").css('maxHeight', height).css('overflow', 'auto');
//     }
  },
  stretch: function() {
    if(this.get('stretch_ratio')) {
      var height = Ember.$(window).height() - 50;
      var width = Ember.$(window).width();
      var modal_width = (width * 0.9);
      if(modal_width > height * this.get('stretch_ratio') * 0.9) {
        modal_width = height * this.get('stretch_ratio') * 0.9;
      }
      Ember.$(this.get('element')).find(".modal-dialog").css('width', modal_width);
    } else if(this.get('full_stretch')) {
      var height = Ember.$(window).height() - 50;
      var width = Ember.$(window).width();
      var modal_width = (width * 0.97);
      Ember.$(this.get('element')).find(".modal-dialog").css('width', modal_width);
    } else if(this.get('desired_width')) {
      var width = Ember.$(window).width();
      var modal_width = (width * 0.9);
      if(this.get('desired_width') < modal_width) {
        modal_width = this.get('desired_width');
      }
      Ember.$(this.get('element')).find(".modal-dialog").css('width', modal_width);
    } else {
      Ember.$(this.get('element')).find(".modal-dialog").css('width', '');
    }
  }.observes('stretch_ratio', 'desired_width'),
  willDestroy: function() {
    if(!this.get('already_closed')) {
      this.set('already_closed', true);
      this.sendAction('closing');
    }
  },
  touchStart: function(event) {
    this.send('close', event);
  },
  mouseDown: function(event) {
    this.send('close', event);
  },
  actions: {
    close: function(event) {
      if(!Ember.$(event.target).hasClass('modal')) {
        return;
      } else {
        event.preventDefault();
        return this.sendAction();
      }
    }
  }
});



