import Ember from 'ember';
import buttonTracker from '../utils/raw_events';
import app_state from '../utils/app_state';
import editManager from '../utils/edit_manager';
import capabilities from '../utils/capabilities';

export default Ember.Component.extend({
  didInsertElement: function() {
    if(app_state.get('speak_mode')) {
      var elem = document.getElementsByClassName('board')[0];
      var board = editManager.controller && editManager.controller.get('model');
      if(board && board.get('id') == elem.getAttribute('data-id')) {
        board.set('fast_html', {
          width: editManager.controller.get('width'),
          height: editManager.controller.get('height'),
          revision: editManager.controller.get('model.current_revision'),
          html: Ember.String.htmlSafe(elem.innerHTML)
        });
      }
    }
  }
});
