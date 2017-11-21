import modal from '../utils/modal';
import i18n from '../utils/i18n';
import capabilities from '../utils/capabilities';
import Button from '../utils/button';
import CoughDrop from '../app';

export default modal.ModalController.extend({
  opening: function() {
    var _this = this;
    _this.set('player', null);
    var host = window.default_host || capabilities.fallback_host;
    if(this.get('model.video.id') && this.get('model.video.type')) {
      this.set('video_url', host + "/videos/" + this.get('model.video.type') + "/" + this.get('model.video.id'));
    } else if(this.get('model.video.url')) {
      var resource = Button.resource_from_url(this.get('model.video.url'));
      if(resource.type == 'video') {
        this.set('video_url', host + "/videos/" + resource.video_type + "/" + resource.id);
      }
    }

    CoughDrop.Videos.track('video_preview', function(event_type) {
      if(event_type == 'ended') {
        _this.send('close');
      } else if(event_type == 'error') {
        _this.set('player', {error: true});
      } else if(event_type == 'embed_error') {
        _this.set('player', {error: true, embed_error: true});
      }
    }).then(function(player) {
      _this.set('player', player);
    });
  },
  closing: function() {
    if(this.get('player') && this.get('player').cleanup) {
      this.get('player').cleanup();
    }
  },
  actions: {
    toggle_video: function() {
      var player = this.get('player');
      if(player) {
        if(player.get('paused')) {
          player.play();
        } else {
          player.pause();
        }
      }
    }
  }
});
