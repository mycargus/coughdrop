import modal from '../utils/modal';
import i18n from '../utils/i18n';
import stashes from '../utils/_stashes';
import utterance from '../utils/utterance';
import CoughDrop from '../app';

export default modal.ModalController.extend({
  opening: function() {
    this.set('copy_result', null);
    var controller = this;
    var utterances = stashes.get('remembered_vocalizations');
    controller.set('model', {});
    var settings = modal.settings_for['share-utterance'];
    controller.set('utterance', settings.utterance);
    var buttons = settings.utterance.filter(function(b) { return !b.ghost; });
    var u = CoughDrop.store.createRecord('utterance', {button_list: settings.utterance, sentence: utterance.sentence(settings.utterance)});
    u.save().then(function(u) {
      controller.set('utterance_record', u);
    }, function() {
      controller.set('utterance_record_error', true);
    });
  },
  sentence: function() {
    if(this.get('utterance')) {
      return utterance.sentence(this.get('utterance'));
    } else {
      return "";
    }
  }.property('utterance'),
  escaped_sentence: function() {
    return encodeURIComponent(this.get('sentence'));
  }.property('sentence'),
  actions: {
    copy_event(res) {
      if(res) {
        this.set('copy_result', {succeeded: true});
      } else {
        this.set('copy_result', {failed: true});
      }
    }
  }
});
