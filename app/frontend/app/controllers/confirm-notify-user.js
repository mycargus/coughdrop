import modal from '../utils/modal';
import persistence from '../utils/persistence';
import i18n from '../utils/i18n';
import CoughDrop from '../app';

export default modal.ModalController.extend({
  opening: function() {
    this.set('loading', false);
    this.set('error', false);
    var end = (new Date()).getTime() + 5000;
    var _this = this;
    var canceled = false;
    this.set('cancel', function() {
      canceled = true;
    })
    var again = function() {
      var now = (new Date()).getTime();
      var diff = Math.round((end - now) / 1000);
      if(diff < 0) {
        diff = 0;
        _this.send('confirm');
      } else if(!canceled) {
        setTimeout(again, 200);
      }
      _this.set('seconds', diff)
    };
    setTimeout(again, 200);
  },
  closing: function() {
    if(this.get('cancel')) {
      this.get('cancel')();
    }
  },
  actions: {
    confirm: function() {
      var _this = this;
      _this.set('loading', true);
      var fallback = function() {
        if(_this.get('model.raw')) {
          stashes.log_event({
            share: {
              utterance: _this.get('model.raw'),
              sentence: _this.get('model.sentence'),
              recipient_id: _this.get('model.user.id'),
              reply_id: _this.get('model.reply_id')
            }
          });
          modal.close('confirm-notify-user');
          modal.success(i18n.t('user_notified', "Message queued to be sent when online."));
        } else {
          this.set('error', true);
        }
      };
      if(!this.get('model.utterance') && this.get('model.raw')) {
        fallback();
      } else {
        persistence.ajax('/api/v1/utterances/' + this.get('model.utterance.id') + '/share', {
          type: 'POST',
          data: {
            sharer_id: app_state.get('referenced_user.id'),
            user_id: this.get('model.user.id')
          }
        }).then(function(data) {
          _this.set('loading', false);
          modal.close('confirm-notify-user');
          modal.success(i18n.t('user_notified', "Message sent!"));
        }, function(err) {
          _this.set('loading', false);
          if(err && err.result && err.result.status >= 400) {
            _this.set('error', true);
          } else {
            fallback();
          }
        });
      }
    }
  }
});
