import modal from '../utils/modal';
import app_state from '../utils/app_state';

export default modal.ModalController.extend({
  opening: function() {
    var user = app_state.get('currentUser');
    if(user) {
      var progress = user.get('preferences.progress') || {};
      progress.speak_mode_intro_done = true;
      user.set('preferences.progress', progress);
      user.save().then(null, function() { });
    }
  }
});
