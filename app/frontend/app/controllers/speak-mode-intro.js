import modal from '../utils/modal';
import app_state from '../utils/app_state';

export default modal.ModalController.extend({
  opening: function() {
    var user = app_state.get('currentUser');
    if(user) {
      var progress = user.get('preferences.progress') || {};

      progress.speak_mode_intro_done = (new Date()).getTime();
      app_state.set('speak-mode-intro', true);
      user.set('preferences.progress', progress);
      user.save().then(null, function() { });
    }
  },
  closing: function() {
    var user = app_state.get('currentUser');
    if(user && !user.get('preferences.progress.speak_mode_intro_done')) {
      var progress = user.get('preferences.progress') || {};

      progress.modeling_intro_done = (new Date()).getTime();
      user.set('preferences', user.get('preferences') || {});
      user.set('preferences.progress', progress);
      user.save().then(null, function() { });
    }
  }
});
