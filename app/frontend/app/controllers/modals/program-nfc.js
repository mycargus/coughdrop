import modal from '../../utils/modal';
import { later as runLater } from '@ember/runloop';
import capabilities from '../../utils/capabilities';
import CoughDrop from '../../app';

export default modal.ModalController.extend({
  opening: function() {
    // check if NFC is available
    // if so, check if it's programmable
    // if so, ask if they want to save data to the NFC tag if possible
    // text box for the label/vocalization, otherwise button render
    // program button at the bottom that starts listening
    var button = this.get('model.button');
    var tag = this.store.createRecord('tag');
    var _this = this;
    _this.set('status', {loading: true});
    _this.set('label', null);
    _this.set('button', null);
    _this.set('update_tag_id', null);
    capabilities.nfc.available().then(function(res) {
      if(res.can_write) {
        _this.set('can_write', true);
        _this.set('write_tag', true);
        _this.set('public', false);
      }
      if(button) {
        tag.set('button', button);
        _this.set('label', button.vocalization || button.label);
      } else {
        _this.set('label', _this.get('model.label') || "");
      }
      if(_this.get('model.listen')) {
        _this.send('program');
      }
      tag.save().then(function() {
        _this.set('status', null);
        _this.set('tag', tag);
      }, function() {
        _this.set('status', {error: true});
      });
    }, function() {
      _this.set('status', {no_nfc: true});
    });
  },
  not_programmable: function() {
    return !!(this.get('status.loading') || this.get('status.error') || this.get('status.no_nfc') || this.get('status.saving') || this.get('status.programming'));
  }.property('status.loading', 'status.error', 'status.no_nfc', 'status.saving', 'status.programming'),
  save_tag: function(tag_id) {
    var _this = this;
    var tag_object = _this.get('tag');
    tag_object.set('tag_id', tag_id);
    tag_object.set('public', !!_this.get('public'));
    _this.set('status', {saving: true});
    tag_object.save().then(function() {
      _this.set('status', {saved: true});
    }, function() {
      _this.set('status', {error_saving: true});
    });
  },
  actions: {
    save: function() {
      var _this = this;
      if(_this.get('label')) {
        _this.save_tag(_this.get('update_tag_id'));
      }
    },
    program: function() {
      var _this = this;
      _this.set('status', {programming: true});
      var tag_object = _this.get('tag');
      capabilities.nfc.prompt().then(function() {
        var handled = false;
        capabilities.nfc.listen('programming', function(tag) {
          if(handled) { return; }
          handled = true;
          if(!_this.get('label') && _this.get('model.listen')) {
            CoughDrop.store.findRecord('tag', tag.id).then(function(tag_object) {
              // save tag to user and close
            }, function() {
              _this.set('update_tag_id', JSON.stringify(tag.id));
              // prompt for label and save
            });
            // ajax lookup
          }
          var finish_tag = function() {
            _this.save_tag(JSON.stringify(tag.id));
            capabilities.nfc.end_prompt();
          };
          if(tag.writeable && _this.get('write_tag')) {
            var opts = {
              uri: "cough://tag/" + tag_object.get('id')
            };
            if(tag.size) {
              // Program in the label as well if there's room
              if(opts.uri.length + (_this.get('label') || '').length < tag.size * 0.85) {
                tag.text = _this.get('label');
              }
            }
            capabilities.nfc.write(opts).then(function() {
              finish_tag();
            }, function() {
              _this.set('status', {error_writing: true});
            });
          } else {
            finish_tag();
          }
        });
        runLater(function() {
          if(handled) { return; }
          handled = true;
          capabilities.nfc.stop_listening('programming').then(function() {
            _this.set('status', {read_timeout: true});
          }, function() {
            _this.set('status', {read_timeout: true});
          });
        }, 10000);
      });
    }
  }
});
