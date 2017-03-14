import Ember from 'ember';
import modal from '../utils/modal';
import app_state from '../utils/app_state';
import stashes from '../utils/_stashes';
import i18n from '../utils/i18n';

export default modal.ModalController.extend({
  opening: function() {
    var labels = app_state.get('label_locale') || this.get('model.board.translations.current_label') || this.get('model.board.locale') || 'en';
    var vocalizations = app_state.get('vocalization_locale') || this.get('model.board.translations.current_vocalization') || this.get('model.board.locale') || 'en';
    this.set('label_locale', labels);
    this.set('vocalization_locale', vocalizations);
    if(labels == vocalizations) { this.set('same_locale', true); }
  },
  update_matching_other: function(stuff, change) {
    if(change == 'label_locale' && this.get('same_locale')) {
      this.set('vocalization_locale', this.get('label_locale'));
    }
  }.observes('label_locale', 'vocalization_locale'),
  locales: function() {
    var locales = this.get('model.board.locales') || [];
    var list = i18n.get('translatable_locales');
    var res = [{name: i18n.t('choose_locale', '[Choose a Language]'), id: ''}];
    for(var key in list) {
      if(locales.indexOf(key) != -1) {
        res.push({name: list[key], id: key});
      }
    }
    res.push({name: i18n.t('unspecified', "Unspecified"), id: ''});
    return res;
  }.property('model.board', 'model.board.locales'),
  actions: {
    set_languages: function() {
      app_state.set('label_locale', this.get('label_locale'));
      stashes.persist('label_locale', this.get('label_locale'));
      app_state.set('vocalization_locale', this.get('vocalization_locale'));
      stashes.persist('vocalization_locale', this.get('vocalization_locale'));
      modal.close({switched: true});
    },
    clear_languages: function() {
      app_state.set('label_locale', null);
      stashes.persist('label_locale', null);
      app_state.set('vocalization_locale', null);
      stashes.persist('vocalization_locale', null);
      modal.close({switched: true});
    }
  }
});
