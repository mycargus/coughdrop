import Ember from 'ember';
import DS from 'ember-data';
import CoughDrop from '../app';
import i18n from '../utils/i18n';
import persistence from '../utils/persistence';
import app_state from '../utils/app_state';

CoughDrop.Image = DS.Model.extend({
  didLoad: function() {
    this.checkForDataURL().then(null, function() { });
    this.set('app_state', app_state);
    this.clean_license();
  },
  url: DS.attr('string'),
  content_type: DS.attr('string'),
  width: DS.attr('number'),
  height: DS.attr('number'),
  pending: DS.attr('boolean'),
  avatar: DS.attr('boolean'),
  badge: DS.attr('boolean'),
  protected: DS.attr('boolean'),
  suggestion: DS.attr('string'),
  external_id: DS.attr('string'),
  search_term: DS.attr('string'),
  license: DS.attr('raw'),
  permissions: DS.attr('raw'),
  file: DS.attr('boolean'),
  filename: function() {
    var url = this.get('url') || '';
    if(url.match(/^data/)) {
      return i18n.t('embedded_image', "embedded image");
    } else {
      var paths = url.split(/\?/)[0].split(/\//);
      var name = paths[paths.length - 1];
      if(!name.match(/\.(png|gif|jpg|jpeg|svg)$/)) {
        name = null;
      }
      return decodeURIComponent(name || 'image');
    }
  }.property('url'),
  clean_license: function() {
    var _this = this;
    ['copyright_notice', 'source', 'author'].forEach(function(key) {
      if(_this.get('license.' + key + '_link')) {
        _this.set('license.' + key + '_url', _this.get('license.' + key + '_url') || _this.get('license.' + key + '_link'));
      }
      if(_this.get('license.' + key + '_link')) {
        _this.set('license.' + key + '_link', _this.get('license.' + key + '_link') || _this.get('license.' + key + '_url'));
      }
    });
  },
  license_string: function() {
    var license = this.get('license');
    if(!license || !license.type) {
      return i18n.t('unknown_license', "Unknown. Assume all rights reserved");
    } else if(license.type == 'private') {
      return i18n.t('all_rights_reserved', "All rights reserved");
    } else {
      return license.type;
    }
  }.property('license', 'license.type'),
  author_url_or_email: function() {
    var license = this.get('license') || {};
    if(license.author_url) {
      return license.author_url;
    } else if(license.author_email) {
      return license.author_email;
    } else {
      return null;
    }
  }.property('license', 'license.author_url', 'license.author_email'),
  check_for_editable_license: function() {
    if(this.get('license') && this.get('id') && !this.get('permissions.edit')) {
      this.set('license.uneditable', true);
    }
  }.observes('license', 'id', 'permissions.edit'),
  personalized_url: function() {
    return CoughDrop.Image.personalize_url(this.get('url'), this.get('app_state.currentUser.user_token'));
  }.property('url', 'app_state.currentUser.user_token'),
  best_url: function() {
    return this.get('data_url') || this.get('personalized_url') || "";
  }.property('personalized_url', 'data_url'),
  checkForDataURL: function() {
    this.set('checked_for_data_url', true);
    var _this = this;
    if(!this.get('data_url') && this.get('personalized_url') && this.get('personalized_url').match(/^http/)) {
      return persistence.find_url(this.get('personalized_url'), 'image').then(function(data_uri) {
        _this.set('data_url', data_uri);
        if(data_uri && data_uri.match(/^file/)) {
          var img = new Image();
          img.src = data_uri;
        }
        return _this;
      });
    } else if(this.get('url') && this.get('url').match(/^data/)) {
      return Ember.RSVP.resolve(this);
    }
    return Ember.RSVP.reject('no image data url');
  },
  checkForDataURLOnChange: function() {
    this.checkForDataURL().then(null, function() { });
  }.observes('personalized_url')
});

CoughDrop.Image.reopenClass({
  personalize_url: function(url, token) {
    url = url || '';
    if(url.match(/api\/v1\//) && url.match(/lessonpix/) && token) {
      return url + "?user_token=" + token;
    }
    return url;
  },
  mimic_server_processing: function(record, hash) {
    if(record.get('data_url')) {
      hash.image.url = record.get('data_url');
      hash.image.data_url = hash.image.url;
    }
    return hash;
  }
});

export default CoughDrop.Image;
