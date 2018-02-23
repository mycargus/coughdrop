import Ember from 'ember';
import Component from '@ember/component';
import $ from 'jquery';
import buttonTracker from '../utils/raw_events';
import app_state from '../utils/app_state';

export default Component.extend({
  touchStart: function(event) {
    this.select(event);
  },
  touchMove: function(event) {
    this.select(event);
  },
  mouseDown: function(event) {
    this.select(event);
  },
  select: function(event) {
    var $cell = $(event.target).closest('div.cell');
    if($cell.length) {
      event.preventDefault();
      this.sendAction('grid_event', 'setGrid', parseInt($cell.attr('data-row'), 10), parseInt($cell.attr('data-col'), 10));
    }
  },
  mouseMove: function(event) {
    var $cell = $(event.target).closest('div.cell');
    if($cell.length) {
      this.sendAction('grid_event', 'hoverGrid', parseInt($cell.attr('data-row'), 10), parseInt($cell.attr('data-col'), 10));
    } else {
      this.sendAction('grid_event', 'hoverOffGrid');
    }
  }
});
