import Ember from 'ember';
import EmberObject from '@ember/object';
import DS from 'ember-data';
import $ from 'jquery';
import CoughDrop from '../app';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';
import modal from '../utils/modal';
import Subscription from '../utils/subscription';
import Utils from '../utils/misc';

CoughDrop.Organization = DS.Model.extend({
  didLoad: function() {
    this.set('total_licenses', this.get('allotted_licenses'));
    this.update_licenses_expire();
  },
  didUpdate: function() {
    this.set('total_licenses', this.get('allotted_licenses'));
    this.update_licenses_expire();
  },
  name: DS.attr('string'),
  permissions: DS.attr('raw'),
  purchase_history: DS.attr('raw'),
  org_subscriptions: DS.attr('raw'),
  default_home_board: DS.attr('raw'),
  home_board_key: DS.attr('string'),
  admin: DS.attr('boolean'),
  allotted_licenses: DS.attr('number'),
  allotted_eval_licenses: DS.attr('number'),
  used_licenses: DS.attr('number'),
  used_evals: DS.attr('number'),
  total_users: DS.attr('number'),
  total_managers: DS.attr('number'),
  total_supervisors: DS.attr('number'),
  extras: DS.attr('boolean'),
  licenses_expire: DS.attr('string'),
  created: DS.attr('date'),
  children_orgs: DS.attr('raw'),
  management_action: DS.attr('string'),
  recent_session_user_count: DS.attr('number'),
  recent_session_count: DS.attr('number'),
  update_licenses_expire: function() {
    if(this.get('licenses_expire')) {
      var m = window.moment(this.get('licenses_expire'));
      if(m.isValid()) {
        this.set('licenses_expire', m.format('YYYY-MM-DD'));
      }
    }
  },
  licenses_available: function() {
    return (this.get('allotted_licenses') || 0) > (this.get('used_licenses') || 0);
  }.property('allotted_licenses', 'total_licenses', 'used_licenses'),
  eval_licenses_available: function() {
    return (this.get('allotted_eval_licenses') || 0) > (this.get('used_evals') || 0);
  }.property('allotted_eval_licenses', 'used_evals'),
  processed_purchase_history: function() {
    var res = [];
    (this.get('purchase_history') || []).forEach(function(e) {
      var evt = $.extend({}, e);
      evt[e.type] = true;
      res.push(evt);
    });
    return res;
  }.property('purchase_history'),
  processed_org_subscriptions: function() {
    var res = [];
    (this.get('org_subscriptions') || []).forEach(function(s) {
      var user = EmberObject.create(s);
      user.set('subscription_object', Subscription.create({user: user}));
      res.push(user);
    });
    return res;
  }.property('org_subscriptions'),
  load_users: function() {
    var _this = this;
    Utils.all_pages('/api/v1/organizations/' + this.get('id') + '/users', {result_type: 'user', type: 'GET', data: {}}).then(function(data) {
      _this.set('all_communicators', data.filter(function(u) { return !u.org_pending; }));
    }, function(err) {
      _this.set('user_error', true);
    });
    Utils.all_pages('/api/v1/organizations/' + this.get('id') + '/supervisors', {result_type: 'user', type: 'GET', data: {}}).then(function(data) {
      _this.set('all_supervisors', data);
    }, function(err) {
      _this.set('user_error', true);
    });
  },
  supervisor_options: function() {
    var res = [{
      id: null,
      name: i18n.t('select_user', "[ Select User ]")
    }];
    (this.get('all_supervisors') || []).forEach(function(sup) {
      res.push({
        id: sup.id,
        name: sup.user_name
      });
    });
    return res;
  }.property('all_supervisors'),
  communicator_options: function() {
    var res = [{
      id: null,
      name: i18n.t('select_user', "[ Select User ]")
    }];
    (this.get('all_communicators') || []).forEach(function(sup) {
      res.push({
        id: sup.id,
        name: sup.user_name
      });
    });
    return res;
  }.property('all_communicators')
});
CoughDrop.Organization.reopenClass({
  mimic_server_processing: function(record, hash) {
    hash.organization.permissions = {
      "view": true,
      "edit": true
    };

    return hash;
  }
});

export default CoughDrop.Organization;
