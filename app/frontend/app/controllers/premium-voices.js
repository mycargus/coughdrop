import Ember from 'ember';
import EmberObject from '@ember/object';
import modal from '../utils/modal';
import speecher from '../utils/speecher';
import capabilities from '../utils/capabilities';
import i18n from '../utils/i18n';
import app_state from '../utils/app_state';
import persistence from '../utils/persistence';
import tts_voices from '../utils/tts_voices';

export default modal.ModalController.extend({
  opening: function() {
    this.refresh_voices();
  },
  closing: function() {
    speecher.refresh_voices();
  },
  refresh_voices: function() {
    var _this = this;
    if(capabilities.installed_app) {
      capabilities.tts.status().then(function() {
        if(app_state.get('currentUser.full_premium') || app_state.get('currentUser.premium_voices.always_allowed')) {
          _this.set('premium_available', true);
        }
      }, function() {
      });
    }

    var all_voices = capabilities.tts.downloadable_voices();
    var res = [];
    this.set('voice_error', null);
    var claimed_voices = this.get('model.user.premium_voices.claimed') || [];
    all_voices.forEach(function(voice) {
      var v = EmberObject.create(voice);
      v.set('male', voice.gender == 'm');
      v.set('female', voice.gender == 'f');
      v.set('adult', voice.age == 'adult');
      v.set('teen', voice.age == 'teen');
      v.set('child', voice.age == 'child');
      if(claimed_voices.indexOf(v.get('voice_id')) >= 0) {
        v.set('claimed', true);
      }

      res.push(v);
    });
    this.set('voices', res);
    capabilities.tts.available_voices().then(function(voices) {
      var set_voices = _this.get('voices') || [];
      voices.forEach(function(voice) {
        var ref_voice = tts_voices.find_voice(voice.voice_id) || voice;
        var found_voice = set_voices.find(function(v) { return v.get('voice_id') == ref_voice.voice_id; });
        if(found_voice) {
          found_voice.set('active', true);
        }
      });
    }, function() {
      _this.set('voice_error', i18n.t('error_loading_voices', "There was an unexpected problem retrieving the premium voices."));
    });
  },
  actions: {
    play_voice: function(voice) {
      var audio = new Audio();
      audio.src = voice.get('voice_sample');
      audio.play();
    },
    download_voice: function(voice) {
      var _this = this;
      voice.set('downloading', true);
      voice.set('download_progress', 0);
      capabilities.wakelock('download_voice', true);
      var data = {voice_id: voice.voice_id, voice_url: voice.get('voice_url'), system: capabilities.system };
      if(capabilities.system == 'Windows') {
        data.voice_url = voice.get('windows_voice_url');
        data.language_url = voice.get('windows_language_url');
        data.language_dir = voice.get('windows_language_dir');
      }

      // claim the voice and get in return a signed download URL
      persistence.ajax('/api/v1/users/' + this.get('model.user.id') + '/claim_voice', {type: 'POST', data: data}).then(function(data) {
        // refresh the user to get the updated list of premium voices claimed by the user
        _this.get('model.user').reload().then(function() {
          // tell the native code to download the voice
          capabilities.tts.download_voice(voice.get('voice_id'), data.download_url, function(status) {
            voice.set('download_progress', Math.round((status.percent || 0.0) * 100));
          }).then(function() {
            voice.set('downloading', false);
            capabilities.wakelock('download_voice', false);
            _this.refresh_voices();
          }, function(e) {
            console.error("error downloading voice", e);
            _this.refresh_voices();
            capabilities.wakelock('download_voice', false);
            _this.set('voice_error', i18n.t('error_downloading_voice', "There was an unexpected problem while trying to download the voice"));
          });
        }, function() {
          capabilities.wakelock('download_voice', false);
          _this.set('voice_error', i18n.t('error_downloading_voice', "There was an unexpected problem while updating the user's voice settings"));
        });
      }, function(err) {
        _this.refresh_voices();
        capabilities.wakelock('download_voice', false);
        if(err && err.result && err.result.error == 'no more voices available') {
          _this.set('voice_error', i18n.t('no_more_voices', "This user has already claimed the maximum number of premium voices and can't claim any more."));
        } else if(!persistence.get('online')) {
          _this.set('voice_error', i18n.t('online_requiest', "You must be online in order to download premium voices."));
        } else {
          _this.set('voice_error', i18n.t('error_finding_voice', "There was an unexpected problem while trying to start downloading the voice."));
        }
      });
    },
    delete_voice: function(voice) {
      var _this = this;
      capabilities.tts.delete_voice(voice.get('voice_id')).then(function(res) {
        _this.refresh_voices();
      }, function(err) {
        _this.refresh_voices();
        _this.set('voice_error', i18n.t('error_deleting_voice', "There was an unexpected problem while trying to delete the voice"));
      });
    }
  }
});
