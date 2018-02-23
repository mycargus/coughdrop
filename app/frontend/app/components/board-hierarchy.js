import Ember from 'ember';
import Component from '@ember/component';

export default Component.extend({
  actions: {
    toggle_board_hierarchy: function(board_id, state) {
      this.get('hierarchy').toggle(board_id, state);
    },
    select_all: function(state) {
      this.get('hierarchy').set_downstream(null, 'selected', true);
    },
  }
});
