import Ember from 'ember';
import Controller from '@ember/controller';
import { later as runLater } from '@ember/runloop';
import $ from 'jquery';
import modal from '../../utils/modal';
import i18n from '../../utils/i18n';
import contentGrabbers from '../../utils/content_grabbers';
import app_state from '../../utils/app_state';
import EmberObject from '@ember/object';

export default Controller.extend({
  queryParams: ['type', 'start', 'end', 'highlighted', 'device_id', 'location_id'],
  reset_params: function() {
    var _this = this;
    _this.set('model', {});
    this.get('queryParams').forEach(function(param) {
      _this.set(param, null);
    });
    this.set('type', 'note');
  },
  filtered_results: function() {
    return !!(this.get('start') || this.get('end') || this.get('device_id') || this.get('location_id'));
  }.property('start', 'end', 'device_id', 'location_id'),
  type: null,
  start: null,
  end: null,
  device_id: null,
  location_id: null,
  title: function() {
    return "Logs for " + this.get('model.user_name');
  }.property('model.user_name'),
  refresh_on_params_change: function() {
    this.send('refresh');
  }.observes('type', 'start', 'end', 'device_id', 'location_id', 'highlighted'),
  messages_only: function() {
    return this.get('type') == 'note';
  }.property('type'),
  all_logs: function() {
    return !this.get('filtered_results') && (!this.get('type') || this.get('type') == 'all') && this.get('highlighted') != '1';
  }.property('type', 'filtered_results', 'highlighted'),
  actions: {
    obl_export: function() {
      modal.open('download-log', {user: this.get('model')});
    },
    recordNote: function(type) {
      var _this = this;
      var user = this.get('model');
      modal.open('record-note', {note_type: type, user: user}).then(function() {
        _this.send('refresh');
      });
    },
    quick_assessment: function() {
      var _this = this;
      app_state.check_for_full_premium(_this.get('model'), 'quick_assessment').then(function() {
        modal.open('quick-assessment', {user: _this.get('model')}).then(function() {
          _this.send('refresh');
        });
      }, function() { });
    },
    refresh: function() {
      if(!this.get('model.id')) { return; }
      var controller = this;
      if(this.get('type') == 'all') { this.set('type', null); }
      var args = {user_id: this.get('model.id')};
      if(this.get('type') && this.get('type') != 'all') {
        args.type = this.get('type');
      }
      if(this.get('highlighted') == '1') {
        args.highlighted = true;
      }
      if(this.get('start')) { args.start = this.get('start'); }
      if(this.get('end')) { args.end = this.get('end'); }
      if(this.get('device_id')) { args.device_id = this.get('device_id'); }
      if(this.get('location_id')) { args.location_id = this.get('location_id'); }

      this.set('logs', {loading: true});

      this.store.query('log', args).then(function(list) {
        controller.set('logs', list.map(function(i) { return i; }));
        var meta = $.extend({}, list.meta);
        controller.set('meta', meta);
        // weird things happen if we try to observe meta.next_url, it stops
        // updating on subsequent requests.. hence this setter.
        controller.set('more_available', !!meta.next_url);

        if(controller.get('type') == 'note' && controller.get('model')) {
          var user = controller.get('model');
          var log = controller.get('logs')[0];
          if(log && log.get('time_id') && user.get('last_message_read') != log.get('time_id')) {
            // TODO: there's a reloadRecord error happening here without the timeout,
            // you should probably figure out the root issue
            runLater(function() {
              user.set('last_message_read', log.get('time_id'));
              user.save().then(null, function() { });
            }, 1000);
          }
        }
      }, function() {
        controller.set('logs', {error: true});
      });
    },
    more: function() {
      var _this = this;
      if(this.get('more_available')) {
        var meta = this.get('meta');
        var args = {user_id: this.get('model.id'), per_page: meta.per_page, offset: (meta.offset + meta.per_page)};
        if(this.get('type') && this.get('type') != 'all') {
          args.type = this.get('type');
        }
        if(this.get('start')) { args.start = this.get('start'); }
        if(this.get('end')) { args.end = this.get('end'); }
        if(this.get('device_id')) { args.device_id = this.get('device_id'); }
        if(this.get('location_id')) { args.location_id = this.get('location_id'); }
        var find = this.store.query('log', args);
        find.then(function(list) {
          _this.set('logs', _this.get('logs').concat(list.map(function(i) { return i; })));
          var meta = $.extend({}, list.meta);
          _this.set('meta', meta);
          _this.set('more_available', !!meta.next_url);
        }, function() { });
      }
    },
    clearLogs: function() {
      modal.open('confirm-delete-logs', {user: this.get('model')});
    }
  }
});
