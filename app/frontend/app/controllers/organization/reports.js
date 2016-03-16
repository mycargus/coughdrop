import Ember from 'ember';
import i18n from '../../utils/i18n';
import persistence from '../../utils/persistence';

export default Ember.Controller.extend({
  queryParams: ['current_report'],
  available_reports: function() {
    if(this.get('model.permissions.edit')) {
      var list = [{id: 'select', name: i18n.t('select_report_prompt', "[ Select a Report ]")}];
      list.push({id: 'all_users', name: i18n.t('all_users', "All organization communicators") });
      list.push({id: 'all_supervisors', name: i18n.t('all_supervisors', "All organization supervisors") });
      if(this.get('model.permissions.manage')) {
        list.push({id: 'recent_sessions', name: i18n.t('recent_sessions', "Recent user sessions") });
      }
      if(this.get('model.admin')) {
        list.push({id: 'new_users', name: i18n.t('new_users', "Signed up in the last 2 weeks") });
        list.push({id: 'recent_3', name: i18n.t('recent_3', "Signed up more than 3 weeks ago, used in the last week")});
        list.push({id: 'logged_2', name: i18n.t('logged_2', "Generated usage logs in the last 2 weeks")});
        list.push({id: 'setup_but_expired', name: i18n.t('setup_but_expired', "Used initially but now expired")});
        list.push({id: 'free_supervisor_without_supervisees', name: i18n.t('free_supervisor_without_supervisees', "Free supervisors without any supervisees")});
        list.push({id: 'unused_3', name: i18n.t('unused_3', "Not used for the last 3 months")});
        list.push({id: 'unused_6', name: i18n.t('unused_6', "Not used for the last 6 months")});
        list.push({id: 'multiple_emails', name: i18n.t('multiple_emails', "Emails with multiple signups")});
        list.push({id: 'current_but_expired', name: i18n.t('current_but_expired', "Used currently but now expired")});
        list.push({id: 'missing_words', name: i18n.t('missing_words', "Button labels that don't have matching parts of speech")});
        list.push({id: 'overridden_parts_of_speech', name: i18n.t('overridden_parts_of_speech', "Manually-set parts of speech")});
        list.push({id: 'missing_symbols', name: i18n.t('missing_symbols', "Search terms that don't return any matching symbols")});
        list.push({id: 'premium_voices', name: i18n.t('premium_voice_downloads', "Premium Voice Downloads")});
        list.push({id: 'totals', name: i18n.t('record_totals', "Total counts")});
      } else {
        list.push({id: 'logged_2', name: i18n.t('logged_2', "Generated usage logs in the last 2 weeks")});
        list.push({id: 'unused_3', name: i18n.t('unused_3', "Not used for the last 3 months")});
        list.push({id: 'unused_6', name: i18n.t('unused_6', "Not used for the last 6 months")});
      }
      return list;
    } else {
      return [];
    }
  }.property('model.permissions.edit', 'model.admin'),
  get_report: function() {
    if(this.get('current_report') && this.get('current_report') != 'select' && this.get('model.id')) {
      var _this = this;
      _this.set('results', {loading: true});
      var list = [];
      var next_page = function(url, limit) {
        persistence.ajax(url, {type: 'GET'}).then(function(data) {
          _this.set('results.loading', false);
          if(data.user) {
            list = list.concat(data.user);
          } else if(data.users) {
            list = list.concat(data.users);
          } else if(data.log) {
            list = list.concat(data.log);
          }
          if(data.meta && data.meta.next_url && (!limit || list.length < limit)) {
            next_page(data.meta.next_url, limit);
            _this.set('results.more', true);
          } else {
            _this.set('results.more', false);
          }
          if(data.stats) {
            list = [];
            var max = 1;
            for(var key in data.stats) {
              max = Math.max(max, data.stats[key]);
            }
            for(var key in data.stats) {
              var obj = {key: key, value: parseInt(data.stats[key], 10), label_class: 'label label-default'};
              if((obj.value / max) > 0.67) {
                obj.label_class = 'label label-danger';
              } else if((obj.value / max) > 0.33) {
                obj.label_class = 'label label-warning';
              }
              list.push(obj);
            }
            list.sort(function(a, b) { return b.value - a.value; });
            _this.set('results.count', list.length);
            _this.set('results.stats', list);
          } else {
            _this.set('results.count', list.length);
            _this.set('results.list', list);
          }
        }, function(err) {
          _this.set('results.loading', false);
          _this.seT('results.error', {error: err.error || i18n.t('unexpected_error', "Unexpected error")});
        });
      };
      if(this.get('current_report') == 'recent_sessions') {
        next_page('/api/v1/organizations/' + _this.get('model.id') + '/logs', 100);
      } else if(this.get('current_report') == 'all_users') {
        next_page('/api/v1/organizations/' + _this.get('model.id') + '/users');
      } else if(this.get('current_report') == 'all_supervisors') {
        next_page('/api/v1/organizations/' + _this.get('model.id') + '/supervisors');
      } else {
        next_page('/api/v1/organizations/' + _this.get('model.id') + '/admin_reports?report=' + _this.get('current_report'));
      }
    } else {
      this.set('results', null);
    }
  }.observes('current_report', 'model.id')
});
