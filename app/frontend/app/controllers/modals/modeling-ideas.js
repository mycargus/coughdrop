import modal from '../../utils/modal';
import app_state from '../../utils/app_state';
import i18n from '../../utils/i18n';
import {set as emberSet, get as emberGet} from '@ember/object';

export default modal.ModalController.extend({
  opening: function() {
    var users = this.get('model.users');
    var user = app_state.get('currentUser');
    var _this = this;
    _this.set('activity_index', 0);
    _this.set('show_target_words', false);
    _this.set('force_intro', false);
    if(user) {
      _this.set('activities', {loading: true});
      user.load_word_activities().then(function(activities) {
        _this.set('activities', activities);
      }, function(err) {
        _this.set('activities', {error: true});
      });
    } else {
      _this.set('activities', {error: true});
    }
  },
  user_activities: function() {
    var res = [];

    var empty_num = 0;
    if(this.get('force_intro') || !app_state.get('currentUser.preferences.progress.modeling_ideas_viewed')) {
      res.push({intro: true});
      empty_num = 1;
    }

    var user_ids = (this.get('model.users') || []).mapBy('id');
    (this.get('activities.list') || []).forEach(function(a) {
      emberSet(a, 'real', true);
      var types = {};
      types[a.type] = true;
      emberSet(a, 'types', types);
      var valids = 0;
      a.user_ids.forEach(function(id) { if(user_ids.indexOf(id) !== -1) { valids++; } });
      if(valids > 0) {
        emberSet(a, 'matching_users', valids);
        res.push(a);
      }
    });
    if(res.length == empty_num) {
      var none_premium = true;
      (this.get('model.users') || []).forEach(function(u) { if(emberGet(u, 'premium')) { none_premium = false; } });
      if(none_premium) {
        res.push({none_premium: true});
      } else {
        res.push({empty: true});
      }
    }
    return res;
  }.property('activities', 'model.users', 'force_intro'),
  user_words: function() {
    var res = [];
    var text_reasons = {
      fallback: i18n.t('starter_word', "Starter Word"),
      primary_words: i18n.t('goal_words', "Goal Target"),
      primary_modeled_words: i18n.t('goal_words', "Goal Target"),
      secondary_words: i18n.t('goal_words', "Goal Target"),
      secondary_modeled_words: i18n.t('goal_words', "Goal Target"),
      popular_modeled_words: i18n.t('modeled_words', "Frequently-Modeled"),
      infrequent_core_words: i18n.t('infrequent_core', "Rarely-Used Core"),
      emergent_words: i18n.t('emergent', "Emergent Use"),
    };
    var user_ids = (this.get('model.users') || []).mapBy('id');
    (this.get('activities.words') || []).forEach(function(w) {
      var valids = 0;
      w.user_ids.forEach(function(id) { if(user_ids.indexOf(id) !== -1) { valids++; } });
      if(valids > 0) {
        emberSet(w, 'matching_users', valids);
        emberSet(w, 'text_reasons', w.reasons.map(function(r) { return text_reasons[r]; }).uniq().compact().join(', '));
        res.push(w);
      }
    });
    return res;
  }.property('activities', 'model.users'),
  words_list: function() {
    return (this.get('user_words') || []).mapBy('word').join(', ');
  }.property('user_words'),
  current_activity: function() {
    var idx = this.get('activity_index') || 0;
    return (this.get('user_activities') || [])[idx];
  }.property('activity_index', 'user_activities'),
  no_next: function() {
    return !((this.get('activity_index') + 1) < this.get('user_activities.length'));
  }.property('activity_index', 'user_activities'),
  no_previous: function() {
    return !!(this.get('activity_index') == 0 || this.get('user_activities.length') == 0 || !this.get('user_activities.length'));
  }.property('activity_index', 'user_activities'),
  actions: {
    next: function() {
      this.set('activity_index', Math.min(this.get('user_activities.length') - 1, this.get('activity_index') + 1));
      this.set('show_target_words', false);

      var user = app_state.get('currentUser');
      if(user && !user.get('preferences.progress.modeling_ideas_viewed')) {
        var progress = user.get('preferences.progress') || {};

        progress.modeling_ideas_viewed = true;
        user.set('preferences.progress', progress);
        user.save().then(null, function() { });
      }
    },
    previous: function() {
      this.set('activity_index', Math.max(0, this.get('activity_index') - 1))
      this.set('show_target_words', false);
    },
    target_words: function() {
      this.set('show_target_words', !this.get('show_target_words'));
    },
    show_intro: function() {
      this.set('force_intro', true);
      this.set('activity_index', 0);
    },
    attempt: function() {
      // TODO: push something to the log
      this.set('current_activity.will_attempt', true);
    },
    dismiss: function() {
      // TODO: push something to the log
      this.set('current_activity.dismissed', true);
    },
    video: function() {
      var url = this.get('current_activity.url');

      var youtube_regex = (/(?:https?:\/\/)?(?:www\.)?youtu(?:be\.com\/watch\?(?:.*?&(?:amp;)?)?v=|\.be\/)([\w \-]+)(?:&(?:amp;)?[\w\?=]*)?/);
      var youtube_match = url && url.match(youtube_regex);
      var youtube_id = youtube_match && youtube_match[1];

      if(youtube_id) {
        modal.open('inline-video', {video: {type: 'youtube', id: youtube_id}});
      }
    }
  }
});
