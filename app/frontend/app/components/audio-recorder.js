import Ember from 'ember';
import contentGrabbers from '../utils/content_grabbers';
import app_state from '../utils/app_state';

export default Ember.Component.extend({
  tagName: 'div',
  willInsertElement: function() {
    var _this = this;
    _this.check_status();
    this.set('model', {});
    contentGrabbers.soundGrabber.setup(null, this);
  },
  willDestroyElement: function() {
    contentGrabbers.soundGrabber.clear_sound_work();
  },
  check_status: function() {
    var _this = this;
    if(!_this.get('sound')) {
      Ember.run.later(function() {
        _this.sendAction('audio_not_ready');
        _this.send('record_sound');
      });
    }
  }.observes('sound', 'id'),
  update_sound: function() {
    if(this.get('model.sound')) {
      this.send('audio_selected', this.get('model.sound'));
    }
  }.observes('model.sound'),
  update_sound_preview: function() {
    if(this.get('sound_preview') && !this.get('sound_preview.transcription') && this.get('text')) {
      this.set('sound_preview.name', this.get('text'));
      this.set('sound_preview.transcription', this.get('text'));
    }
  }.observes('sound_preview'),
  show_next_phrase: function() {
    return this.get('next_phrase') && !this.get('browse_audio') && !this.get('sound_preview');
  }.property('next_phrase', 'browse_audio', 'sound_preview', 'sound_recording', 'sound'),
  actions: {
    toggle: function() {

    },
    browse_audio: function() {
      contentGrabbers.soundGrabber.browse_audio();
    },
    record_sound: function() {
      contentGrabbers.soundGrabber.record_sound(true);
      Ember.run.later(function() {
        Ember.$("#recording_status").focus();
      }, 100);
    },
    toggle_recording_sound: function(action) {
      contentGrabbers.soundGrabber.toggle_recording_sound(action);
    },
    audio_selected: function(sound) {
      this.set('sound', sound);
      this.sendAction('audio_ready', sound);
      contentGrabbers.soundGrabber.clear_sound_work();
    },
    select_sound_preview: function() {
      contentGrabbers.soundGrabber.select_sound_preview();
    },
    clear_sound: function() {
      this.sendAction('audio_not_ready');
    },
    clear_sound_work: function() {
      contentGrabbers.soundGrabber.clear_sound_work();
      this.send('record_sound');
    },
    select_phrase: function(id) {
      this.sendAction('select_phrase', id);
    },
    decide_on_recording: function(decision) {
      this.sendAction('decide_on_recording', decision);
    }
  }
});
