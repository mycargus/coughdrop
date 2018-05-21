import Ember from 'ember';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import modal from '../utils/modal';
import persistence from '../utils/persistence';

export default modal.ModalController.extend({
  opening: function() {
    this.set('persistence', persistence);
  },
  details: function() {
    var details = ([].concat(persistence.get('sync_log') || [])).reverse();
    (details || []).forEach(function(sync) {
      emberSet(sync, 'cached', sync.statuses.filter(function(s) { return s.status == 'cached'; }).length);
      emberSet(sync, 'downloaded', sync.statuses.filter(function(s) { return s.status == 'downloaded'; }).length);
      emberSet(sync, 're_downloaded', sync.statuses.filter(function(s) { return s.status == 're-downloaded'; }).length);
      sync.statuses.forEach(function(s) {
        emberSet(s, (s.status || '').replace(/-/, '_'), true);
      });
    });
    return details;
  }.property('persistence.sync_log', 'persistence.sync_log.length', 'persistence.sync_log.@each.status'),
  refreshing_class: function() {
    var res = "glyphicon glyphicon-refresh ";
    if(this.get('persistence.syncing')) {
      res = res + "spinning ";
    }
    return res;
  }.property('persistence.syncing'),
  first_log_date: function() {
    var log = this.get('stashes.usage_log')[0];
    if(log) {
      return new Date(log.timestamp * 1000);
    }
    return null;
  }.property('stashes.usage_log.length'),
  actions: {
    toggle_statuses: function(sync) {
      emberSet(sync, 'toggled', !emberGet(sync, 'toggled'));
    },
    cancel_sync: function() {
      if(persistence.get('syncing')) {
        persistence.cancel_sync();
      }
    },
    sync: function() {
      if(!persistence.get('syncing')) {
        console.debug('syncing because manually triggered');
        persistence.sync('self', true).then(null, function() { });
      }
    },
  }
});
