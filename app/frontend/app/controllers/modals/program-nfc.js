import modal from '../../utils/modal';
import { later as runLater } from '@ember/runloop';
import capabilities from '../../utils/capabilities';

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
  actions: {
    program: function() {
      var _this = this;
      _this.set('status', {programming: true});
      var tag_object = _this.get('tag');
      capabilities.prompt().then(function() {
        var handled = false;
        capabilities.nfc.listen('programming', function(tag) {
          if(handled) { return; }
          handled = true;
          var finish_tag = function() {
            tag_object.set('tag_id', JSON.stringify(tag.id));
            tag_object.set('public', !!_this.get('public'));
            tag_object.set('label', _this.get('label'));
            _this.set('status', {saving: true});
            tag_object.save().then(function() {
              _this.set('status', {saved: true});
            }, function() {
              _this.set('status', {error_saving: true});
            })
            capabilities.nfc.end_prompt();
          };
          if(tag.writeable && _this.get('write_tag')) {
            capabilities.nfc.write({
              text: _this.get('label'),
              uri: "cough://tag/" + tag_object.get('id')
            }).then(function() {
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
