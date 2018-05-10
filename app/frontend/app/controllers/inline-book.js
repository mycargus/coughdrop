import modal from '../utils/modal';
import i18n from '../utils/i18n';
import CoughDrop from '../app';

export default modal.ModalController.extend({
  opening: function() {
    var _this = this;
  },
  book_url: function() {
    return "https://tools.openaac.org/tarheel/launch#" + this.get('model.url');
  }.property('model.url'),
  actions: {
  }
});
