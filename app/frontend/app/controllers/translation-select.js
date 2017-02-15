import Ember from 'ember';
import modal from '../utils/modal';
import BoardHierarchy from '../utils/board_hierarchy';
import i18n from '../utils/i18n';
import app_state from '../utils/app_state';

export default modal.ModalController.extend({
  opening: function() {
    var _this = this;
    _this.set('hierarchy', {loading: true});
    BoardHierarchy.load_with_button_set(this.get('model.board'), {deselect_on_different: true, prevent_different: true}).then(function(hierarchy) {
      _this.set('hierarchy', hierarchy);
    }, function(err) {
      _this.set('hierarchy', {error: true});
    });
  },
  locales: function() {
    var list = i18n.get('translatable_locales');
    var res = [{name: i18n.t('choose_locale', '[Choose a Language]'), id: ''}];
    for(var key in list) {

      res.push({name: list[key], id: key});
    }
    res.push({name: i18n.t('unspecified', "Unspecified"), id: ''});
    return res;
  }.property(),
  actions: {
    translate: function() {
      var _this = this;
      var board_ids_to_include = null;
      if(this.get('hierarchy')) {
        board_ids_to_include = this.get('hierarchy').selected_board_ids();
      }

      var translate_opts = {
        board: _this.get('model.board'),
        copy: _this.get('model.board'),
        button_set: _this.get('model.board.button_set'),
        locale: _this.get('translate_locale'),
        old_board_ids_to_translate: board_ids_to_include,
        new_board_ids_to_translate: board_ids_to_include
      };

      return modal.open('button-set', translate_opts).then(function(res) {
        if(res && res.translated) {
          return _this.get('model.board').reload(true).then(function() {
            app_state.set('board_reload_key', Math.random() + "-" + (new Date()).getTime());
          });
        }
      });
    },
  }
});
