import modal from '../utils/modal';
import capabilities from '../utils/capabilities';
import stashes from '../utils/_stashes';
import utterance from '../utils/utterance';
import CoughDrop from '../app';
import { later as runLater } from '@ember/runloop';

export default modal.ModalController.extend({
  opening: function() {
    this.set('copy_result', null);
    var controller = this;
    controller.set('model', {});
    var settings = modal.settings_for['share-utterance'];
    controller.set('utterance', settings.utterance);
    var u = CoughDrop.store.createRecord('utterance', {button_list: settings.utterance, sentence: utterance.sentence(settings.utterance)});
    u.save().then(function(u) {
      controller.set('utterance_record', u);
    }, function() {
      controller.set('utterance_record_error', true);
    });
    this.check_native_shares();
  },
  contacts: function() {
    if(app_state.get('referenced_user.supporter_role')) {
      return app_state.get('referenced_user.supervisees') || [];
    } else {
      return app_state.get('referenced_user.supervisors') || [];
    }
  }.property('app_state.referenced_user.supervisors', 'app_state.referenced_user.supervisees', 'app_state.referenced_user.supporter_role'),
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
  check_native_shares: function() {
    var _this = this;
    _this.set('native', {});
    capabilities.sharing.available().then(function(list) {
      if(list.indexOf('facebook') != -1) { _this.set('native.facebook', true); }
      if(list.indexOf('twitter') != -1) { _this.set('native.twitter', true); }
      if(list.indexOf('instagram') != -1) { _this.set('native.instagram', true); }
      if(list.indexOf('email') != -1) { _this.set('native.email', true); }
      if(list.indexOf('clipboard') != -1) { _this.set('native.clipboard', true); }
      if(list.indexOf('generic') != -1) { _this.set('native.generic', true); }
    });
  },
  shares: function() {
    var res = {};
    if(this.get('utterance_record.link')) {
      res.facebook = true;
      res.twitter = true;
    }
    var native = this.get('native');
    for(var key in native) {
      if(native[key] && this.get('utterance_record.link')) {
        res[key] = true;
      }
    }
    if(!this.get('utterance.best_image_url')) {
      res.instagram = false;
    }
    if(document.queryCommandSupported && document.queryCommandSupported('copy')) {
      res.clipboard = true;
    }
    return res;
  }.property('utterance_record.link', 'native', 'native.generic', 'native.facebook', 'native.twitter', 'native.instagram', 'native.clipboard'),
  facebook_url: function() {
    return 'https://www.facebook.com/sharer/sharer.php?u=' + encodeURIComponent(this.get('utterance_record.link'));
  }.property('utterance_record.link'),
  twitter_url: function() {
    return 'https://twitter.com/intent/tweet?url=' + encodeURIComponent(this.get('utterance_record.link')) + '&text=' + encodeURIComponent(this.get('sentence')) + '&related=CoughDropAAC';
  }.property('utterance_record.link', 'sentence'),
  actions: {
    copy_event(res) {
      if(res) {
        this.set('copy_result', {succeeded: true});
        runLater(function() {
          modal.close();
        }, 3000);
      } else {
        this.set('copy_result', {failed: true});
      }
    },
    message: function(user) {
      modal.open('confirm-notify-user', {user: user, raw: this.get('utterance'), sentence: this.get('sentence'), utterance: this.get('utterance_record')});
    },
    share_via: function(medium) {
      if(this.get('native.' + medium)) {
        // TODO: download the image locally first??
        capabilities.sharing.share(medium, this.get('sentence'), this.get('utterance_record.link'), this.get('utterance_record.best_image_url'));
        modal.close();
      } else if(medium == 'facebook') {
        capabilities.window_open(this.get('facebook_url'));
        modal.close();
      } else if(medium == 'twitter') {
        capabilities.window_open(this.get('twitter_url'));
        modal.close();
      } else if(medium == 'email') {
        modal.open('share-email', {url: this.get('utterance_record.link'), text: this.get('sentence'), utterance_id: this.get('utterance_record.id') });
      } else if(medium == 'clipboard' && this.get('shares.clipboard')) {
        var $elem = $("#utterance_sentence");
        window.getSelection().removeAllRanges();
        var text = $elem[0].innerText;
        if($elem[0].tagName == 'INPUT') {
          $elem.focus().select();
          text = $elem.val();
        } else {
          var range = document.createRange();
          range.selectNode($elem[0]);
          window.getSelection().addRange(range);
        }
        var res = document.execCommand('copy');
        if(!res) {
          var textArea = document.createElement('textArea');
          textArea.value = text;
          document.body.appendChild(textArea);
          var range = document.createRange();
          range.selectNodeContents(textArea);
          var selection = window.getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
          textArea.setSelectionRange(0, 999999);        
          res = document.execCommand('copy');
          document.body.removeChild(textArea);
        }
        window.getSelection().removeAllRanges();
        this.send('copy_event', !!res);
      }
    }
  }
});
