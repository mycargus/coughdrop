import Ember from 'ember';
import modal from '../../utils/modal';
import stashes from '../../utils/_stashes';
import $ from 'jquery';
import app_state from '../../utils/app_state';
import utterance from '../../utils/utterance';
import CoughDrop from '../../app';
import { set as emberSet } from '@ember/object';
import { htmlSafe } from '@ember/string';
import { later as runLater } from '@ember/runloop';

export default modal.ModalController.extend({
  opening: function() {
    var buttons = [];
    (stashes.get('working_vocalization') || []).forEach(function(button) {
      var button = $.extend({}, button);
      buttons.push(button);
    });
    this.set('buttons', buttons);
    this.set('ghost_index', null);
    this.set('insertion', null);
    this.set('button_index', buttons.length - 1);
    this.set('buttons', stashes.get('working_vocalization'));
  },
  closing: function() {
    alert('reset sentence box cursor unless it was just set');
  },
  update_selected: function() {
    var buttons = this.get('buttons') || [];
    var idx = this.get('button_index');
    if(idx == null) { idx = buttons.length - 1; }
    if(idx > buttons.length - 1) { idx = buttons.length - 1; }
    if(idx < -1) { idx = -1;}
    var selection = this.get('selection');
    buttons.forEach(function(b, jdx) {
      if(idx == jdx) {
        if(b == selection) {
          emberSet(b, 'cursor_class', htmlSafe('cursor_box selected'));
        } else {
          emberSet(b, 'cursor_class', htmlSafe('cursor_box over'));
        }
      } else if(idx == -1 && jdx == 0) {
        emberSet(b, 'cursor_class', htmlSafe('cursor_box prior'));
      } else {
        emberSet(b, 'cursor_class', htmlSafe('cursor_box'));
      }
    });
    var _this = this;
    runLater(function() {
      _this.snap_scroll();
    });
  }.observes('buttons', 'button_index', 'selection', 'ghost_index'),
  snap_scroll: function() {
    var elem = document.getElementsByClassName('cursor_area')[0];
    if(!elem) { return; }

    var box_bounds = document.getElementsByClassName('cursor_box')[0].getBoundingClientRect();
    // this.set('not_scrollable', false);
    var styles = window.getComputedStyle(elem, null)
    var paddingRight = (parseInt(styles.getPropertyValue('padding-right'), 10) || 0) - (parseInt(styles.getPropertyValue('padding-left'), 10) || 0);
    var cols = Math.floor((elem.clientWidth) / box_bounds.width);
    this.set('columns', cols);
    var idx = this.get('ghost_index') || this.get('button_index') || 0;
    if(idx < 0) { idx = 0; }
    var buttons = this.get('buttons') || [];
    this.set('rows', Math.floor(buttons.length / cols));
    var row = Math.floor(idx / cols);
    if(elem.scrollHeight > elem.clientHeight) {
      elem.scrollTop = box_bounds.height * (row - 1);
    } else {
      elem.scrollTop = 0;
    }

  },
  actions: {
    done: function() {
      var buttons = this.get('buttons');
      utterance.set('rawButtonList', buttons);
      utterance.set('list_vocalized', false);
      modal.close();
    },
    insert: function() {
      var buttons = [].concat(this.get('buttons') || []);
      var idx = this.get('button_index');
      var button = buttons[idx];
      if((button || idx == -1) && this.get('insertion')) {
        var new_button = {
          label: this.get('insertion'),
          modeling: true,
          type: 'speak'
        };
        if(this.get('selection') && idx != -1) {
          buttons[idx] = new_button;
          this.set('buttons', buttons);
          this.set('selection', new_button);
        } else {
          var pre = buttons.slice(0, idx + 1);
          var post = buttons.slice(idx + 1);
          var list = pre.concat([new_button]).concat(post);
          this.set('buttons', list);
          this.set('button_index', idx + 1);
        }
      }
    },
    remove: function() {
      var buttons = this.get('buttons') || [];
      var idx = this.get('button_index');
      var button = buttons[idx];
      if(button) {
        buttons = buttons.filter(function(b) { return b != button; });
      }
      this.set('buttons', buttons);
      this.set('button_index', idx - 1);
      this.set('selection', null);
    },
    select: function(button) {
      var buttons = this.get('buttons') || [];
      if((!button && this.get('selection')) || (button && button == this.get('selection'))) {
        this.set('selection', null);
        this.set('ghost_index', null);
        this.set('insertion', null);
        return;
      }
      var idx = this.get('button_index');
      if(idx == -1) { idx = 0; }
      if(idx == null) { idx = buttons.length; }
      var ref_button = buttons[idx];
      if(!button || ref_button == button) {
        button = button || ref_button;
        this.set('selection', button);
        if(button.label) {
          this.set('insertion', button.vocalization || button.label);
        }
      } else {
        idx = buttons.indexOf(button);
        this.set('insertion', null);
      }
      this.set('button_index', idx);
    },
    move: function(direction) {
      var buttons = this.get('buttons') || [];
      var idx = this.get('button_index');
      var rows = this.get('rows');
      var cols = this.get('columns');
      if(idx == null) { idx =  buttons.length - 1; }
      if(this.get('selection')) {
        if(direction == 'back' || direction == 'forward') {
          this.set('ghost_index', null);
        } else if(!this.get('ghost_index')) {
          this.set('ghost_index', this.get('button_index'));
        }
        var idx = this.get('ghost_index') || this.get('button_index');
        if(direction == 'back' || direction == 'forward') {
          var movement = direction == 'back' ? -1 : 1;
          var prior = buttons[idx + movement];
          var button = buttons[idx];
          var new_list = [].concat(buttons);
          if(button && prior) {
            new_list[idx] = prior;
            new_list[idx + movement] = button;
            this.set('buttons', new_list);
            idx = idx + movement;
            this.set('selection', button);
          }
        } else if(direction == 'up') {
          if(rows != null && cols != null) {
            idx = idx - cols;
          }
        } else if(direction == 'down') {
          if(rows != null && cols != null) {
            idx = Math.max(idx, 0) + cols;
          }
        }
        // in this case up and down should change the scroll
        // without changing the button index
      } else {
        this.set('ghost_index', null);
        if(direction == 'back') {
          idx--;
        } else if(direction == 'forward') {
          idx++;
        } else if(direction == 'up') {
          if(rows != null && cols != null) {
            idx = idx - cols;
          }
        } else if(direction == 'down') {
          if(rows != null && cols != null) {
            idx = Math.max(idx, 0) + cols;
          }
        }
      }
      if(idx > buttons.length - 1) { idx = buttons.length - 1; }
      if(idx < -1) { idx = -1;}
      if(this.get('ghost_index')) {
        this.set('ghost_index', idx);
      } else {
        this.set('button_index', idx);
      }
    }
  }
});
