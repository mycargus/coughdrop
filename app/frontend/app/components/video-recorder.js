import Ember from 'ember';
import Component from '@ember/component';
import { later as runLater } from '@ember/runloop';
import contentGrabbers from '../utils/content_grabbers';
import app_state from '../utils/app_state';

export default Component.extend({
  tagName: 'div',
  willInsertElement: function() {
    var _this = this;
    runLater(function() {
      _this.sendAction('video_not_ready');
      contentGrabbers.videoGrabber.setup(_this);
      _this.set('app_state', app_state);
    });
  },
  willDestroyElement: function() {
    contentGrabbers.videoGrabber.clear_video_work();
  },
  time_recording: function() {
    if(this.get('video_recording.started')) {
      var now = (new Date()).getTime();
      return Math.round((now - this.get('video_recording.started')) / 1000);
    } else {
      return null;
    }
  }.property('video_recording.started', 'app_state.short_refresh_stamp'),
  video_allowed: function() {
    // must have an active paid subscription to access video logs on your account
    return this.get('user.full_premium');
  }.property('user', 'user.full_premium'),
  actions: {
    setup_recording: function() {
      contentGrabbers.videoGrabber.record_video();
    },
    record: function() {
      contentGrabbers.videoGrabber.toggle_recording_video('start');
    },
    stop: function() {
      contentGrabbers.videoGrabber.toggle_recording_video('stop');
    },
    play: function() {
      contentGrabbers.videoGrabber.play();
    },
    clear: function() {
      contentGrabbers.videoGrabber.clear_video_work();
    },
    swap: function() {
      contentGrabbers.videoGrabber.swap_streams();
    },
    keep: function() {
      contentGrabbers.videoGrabber.select_video_preview();
    }
  }
});
