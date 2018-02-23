import Ember from 'ember';
import EmberObject from '@ember/object';
import {set as emberSet, get as emberGet} from '@ember/object';
import modal from '../utils/modal';
import app_state from '../utils/app_state';
import i18n from '../utils/i18n';
import contentGrabbers from '../utils/content_grabbers';
import Utils from '../utils/misc';
import CoughDrop from '../app';

export default modal.ModalController.extend({
  opening: function() {
    var _this = this;
    contentGrabbers.avatar_result = function(success, result) {
      _this.set('loading_avatar', false);
      if(success) {
        if(result == 'loading') {
          _this.set('loading_avatar', true);
        } else {
          _this.set('model.user.avatar_url', result.get('url'));
        }
      } else {
        modal.error(i18n.t('avatar_upload_failed', "Profile pic failed to upload"));
      }
    };
  },
  closing: function() {
    contentGrabbers.avatar_result = null;
  },
  avatar_examples: CoughDrop.avatarUrls.concat(CoughDrop.iconUrls),
  avatar_options: function() {
    var res = [];
    if(this.get('model.user.avatar_url')) {
      res.push({selected: true, alt: i18n.t('current_avatar', 'current pic'), url: this.get('model.user.avatar_url')});
    }
    (this.get('model.user.prior_avatar_urls') || []).forEach(function(url, idx) {
      res.push({alt: i18n.t('prior_idx', "prior pic %{idx}", {idx: idx}), url: url});
    });
    res = res.concat(this.get('avatar_examples'));
    if(this.get('model.user.fallback_avatar_url')) {
      res.push({alt: i18n.t('fallback', 'fallback'), url: this.get('model.user.fallback_avatar_url')});
    }
    res.forEach(function(option) {
      var url = option.url.replace(/\(/, '\\(').replace(/\)/, '\\)'); //Ember.Handlebars.Utils.escapeExpression(option.url).replace(/\(/, '\\(').replace(/\)/, '\\)');
      option.div_style = "height: 0; width: 100%; padding-bottom: 100%; overflow: hidden; background-position: center; background-repeat: no-repeat; background-size: contain; background-image: url(" + url + ");";
    });
    res = Utils.uniq(res, function(o) { return o.url; });
    return res;
  }.property('model.user.prior_avatar_urls', 'model.user.fallback_avatar_url', 'mode.user.avatar_url'),
  update_selected: function() {
    var url = this.get('model.user.avatar_url');
    if(url && this.get('avatar_options')) {
      this.get('avatar_options').forEach(function(o) {
        emberSet(o, 'selected', o.url == url);
      });
    }
  }.observes('model.user.avatar_url'),
  actions: {
    pick: function(option) {
      this.set('model.user.avatar_url', option.url);
    },
    select: function() {
      var user = this.get('model.user');
      user.set('avatar_data_uri', null);
      user.save().then(function() {
        user.checkForDataURL().then(null, function() { });
        modal.close();
      }, function() {
        modal.error(i18n.t('avatar_update_failed', "Failed to save updated avatar"));
      });
    }
  }
});

