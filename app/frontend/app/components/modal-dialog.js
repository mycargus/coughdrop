import Ember from 'ember';
import Component from '@ember/component';
import $ from 'jquery';
import capabilities from '../utils/capabilities';
import modal from '../utils/modal';

export default Component.extend({
  didRender: function() {
    this.stretch();
    if(!this.get('already_opened')) {
      this.set('already_opened', true);
      this.sendAction('opening');
    }
    this.set('auto_close', !!modal.auto_close);
//     if(capabilities.mobile) {
      var height = $(window).height() - 50;
      $(this.get('element')).find(".modal-content").css('maxHeight', height).css('overflow', 'auto');
//     }
  },
  willClearRender: function() {
    this.set('already_opened', false);
  },
  stretch: function() {
    if(this.get('stretch_ratio')) {
      var height = $(window).height() - 50;
      var width = $(window).width();
      var modal_width = (width * 0.9);
      if(modal_width > height * this.get('stretch_ratio') * 0.9) {
        modal_width = height * this.get('stretch_ratio') * 0.9;
      }
      $(this.get('element')).find(".modal-dialog").css('width', modal_width);
    } else if(this.get('full_stretch')) {
      var height = $(window).height() - 50;
      var width = $(window).width();
      var modal_width = (width * 0.97);
      $(this.get('element')).find(".modal-dialog").css('width', modal_width);
    } else if(this.get('desired_width')) {
      var width = $(window).width();
      var modal_width = (width * 0.9);
      if(this.get('desired_width') < modal_width) {
        modal_width = this.get('desired_width');
      }
      $(this.get('element')).find(".modal-dialog").css('width', modal_width);
    } else {
      $(this.get('element')).find(".modal-dialog").css('width', '');
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
      if(!$(event.target).hasClass('modal')) {
        return;
      } else {
        try {
          event.preventDefault();
        } catch(e) { }
        return this.sendAction();
      }
    },
    any_select: function() {
      modal.auto_close = false;
      this.set('auto_close', !!modal.auto_close);
    }
  }
});



