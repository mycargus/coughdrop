import Ember from 'ember';
import Controller from '@ember/controller';
import CoughDrop from '../../app';
import modal from '../../utils/modal';
import Utils from '../../utils/misc';
import i18n from '../../utils/i18n';
import progress_tracker from '../../utils/progress_tracker';
import persistence from '../../utils/persistence';

export default Controller.extend({
  registration_types: CoughDrop.registrationTypes,
  allow_shares_options: [
    {name: i18n.t('email_shares', "Email Me When People I Supervise Share a Message with Me"), id: 'email'},
    {name: i18n.t('text_shares', "Text Me When People I Supervise Share a Message with Me"), id: 'text'},
    {name: i18n.t('app_shares', "Show In the App When People I Supervise Share a Message with Me"), id: 'app'}
  ],
  notification_frequency_options: [
    {name: i18n.t('no_notifications', "Don't Email Me Communicator Reports"), id: ''},
    {name: i18n.t('weekly_notifications', "Email Me Weekly Communicator Reports"), id: '1_week'},
    {name: i18n.t('text_shares', "Email Me Communicator Reports Every Two Weeks"), id: '2_weeks'},
    {name: i18n.t('app_shares', "Email Me Monthly Communicator Reports"), id: '1_month'}
  ],
  goal_notification_options: [
    {name: i18n.t('email_goal_completion', "Email Me When Goals are Completed or Badges are Earned"), id: 'enabled'},
    {name: i18n.t('dont_email_goal_completion', "Don't Email Me When Goals are Completed or Badges are Earned"), id: 'disabled'}
  ],
  title: function() {
    return "Edit " + this.get('model.user_name');
  }.property('model.user_name'),
  load_webhooks: function() {
    var _this = this;
    _this.set('webhooks', {loading: true});
    Utils.all_pages('webhook', {user_id: this.get('model.id')}, function(partial) {
    }).then(function(res) {
      _this.set('webhooks', res);
    }, function(err) {
      _this.set('webhooks', {error: true});
    });
  },
  tools: function() {
    if(this.get('model.integrations') && this.get('model.integrations').length > 0) {
      return this.get('model.integrations').filter(function(i) { return i.get('icon_url'); });
    } else {
      return null;
    }
  }.property('model.integrations'),
  load_integrations: function(reload) {
    var _this = this;
    this.get('model').check_integrations(reload);
  }.observes('model.id'),
  actions: {
    pick_avatar: function() {
      modal.open('pick-avatar', {user: this.get('model')});
    },
    enable_change_password: function() {
      this.set('change_password', true);
    },
    saveProfile: function() {
      // TODO: add a "save pending..." status somewhere
      var user = this.get('model');
      user.set('preferences.progress.profile_edited', true);
      var _this = this;
      user.save().then(function(user) {
        user.set('password', null);
        _this.transitionToRoute('user', user.get('user_name'));
      }, function(err) {
        if(err.responseJSON && err.responseJSON.errors && err.responseJSON.errors[0] == "incorrect current password") {
          modal.error(i18n.t('incorrect_password', "Incorrect current password"));
        } else {
          modal.error(i18n.t('save_failed', "Save failed."));
        }

      });
    },
    cancelSave: function() {
      var user = this.get('model');
      user.rollbackAttributes();
      this.transitionToRoute('user', user.get('user_name'));
    },
    manage_connections: function() {
      this.set('managing_connections', !this.get('managing_connections'));
      if(this.get('managing_connections')) {
        this.load_webhooks();
      }
    },
    add_webhook: function() {
      var _this = this;
      modal.open('add-webhook', {user: this.get('model')}).then(function(res) {
        if(res && res.created) {
          _this.load_webhooks();
        }
      });
    },
    delete_webhook: function(webhook) {
      var _this = this;
      modal.open('confirm-delete-webhook', {user: this.get('model'), webhook: webhook}).then(function(res) {
        if(res && res.deleted) {
          _this.load_integrations(true);
          _this.load_webhooks();
        }
      });
    },
    test_webhook: function(webhook) {
      modal.open('test-webhook', {user: this.get('model'), webhook: webhook});
    },
    add_integration: function() {
      var _this = this;
      modal.open('add-integration', {user: this.get('model')}).then(function(res) {
        if(res && res.created) {
          _this.load_integrations(true);
          _this.load_webhooks();
        }
      });
    },
    browse_tools: function(tool) {
      var _this = this;
      modal.open('add-tool', {user: this.get('model'), tool: tool}).then(function(res) {
        if(res && res.added) {
          _this.load_integrations(true);
          _this.load_webhooks();
        }
      });
    },
    integration_details: function(integration) {
      modal.open('integration-details', {integration: integration, user: this.get('model')});
    },
    delete_integration: function(integration) {
      var _this = this;
      modal.open('confirm-delete-integration', {user: this.get('model'), integration: integration}).then(function(res) {
        if(res && res.deleted) {
          _this.load_integrations(true);
          _this.load_webhooks();
        }
      });
    },
    delete_user: function() {
      modal.open('modals/confirm-delete-user', {user: this.get('model')});
    }
  }
});
