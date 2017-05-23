import Ember from 'ember';
import editManager from '../utils/edit_manager';
import stashes from '../utils/_stashes';
import modal from '../utils/modal';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import CoughDrop from '../app';
import contentGrabbers from '../utils/content_grabbers';
import persistence from '../utils/persistence';

export default Ember.Route.extend({
  model: function(params) {
    // TODO: when on the home screen if you have a large board and hit to open
    // it, it takes a while to change views. This does not, however, happen
    // if you hit the same board in the 'popular boards' list since those
    // views already have a record for the board, albeit a limited one
    // that must be reloaded..
    if(params.key && params.key.match(/^integrations\//)) {
      var parts = params.key.split(/\//);
      var id = parts[1];
      parts = id.split(/:/);
      var integration_id = parts.shift();
      if(app_state.get('sessionUser.global_integrations.' + integration_id)) {
        integration_id = app_state.get('sessionUser.global_integrations.' + integration_id);
      } else if(stashes.get('global_integrations.' + integration_id)) {
        integration_id = stashes.get('global_integrations.' + integration_id);
      }
      var action = parts.join(':');
      var obj = CoughDrop.store.createRecord('board');
      obj.set('integration', true);
      obj.set('key', params.key);
      obj.set('id', 'i' + integration_id);
      return CoughDrop.store.findRecord('integration', integration_id).then(function(tool) {
        var reload = Ember.RSVP.resolve(tool);
        if(!tool.get('render_url')) {
          reload = tool.reload();
        }
        return reload.then(function(tool) {
          var user_token = tool.get('user_token');
          if(user_token && app_state.get('currentUser.id') != app_state.get('sessionUser.id')) {
            user_token = user_token + ":as_user_id=" + app_state.get('currentUser.id');
          }
          obj.set('embed_url', tool.get('render_url'));
          obj.set('integration_name', tool.get('name') || i18n.t('external_integration', "External Integration"));
          obj.set('user_token', user_token);
          obj.set('action', action);
          return Ember.RSVP.resolve(obj);
        }, function(err) {
          return Ember.RSVP.resolve(obj);
        });
      }, function(err) {
        return Ember.RSVP.resolve(obj);
      });
    } else {
      var obj = this.store.findRecord('board', params.key);
      return obj.then(function(data) {
        data.set('lookup_key', params.key);
        return Ember.RSVP.resolve(data);
      }, function(err) {
        var res = CoughDrop.store.createRecord('board', {id: 'bad', key: params.key});
        res.set('lookup_key', params.key);
        res.set('error', err);
        return Ember.RSVP.resolve(res);
      });
    }
  }
});
