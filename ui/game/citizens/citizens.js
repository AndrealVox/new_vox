App.StonehearthCitizensView.reopen({

   didInsertElement: function () {
      var self = this;
      self._super();

      this.$('#promote_to_job').remove();
   },

   selected_commands: function () {
      var filter_fn = function (uri, data) {
         if (data.visible_in_citizens_view === false) {
            return false;
         }
      };
      var commands = radiant.map_to_array(this.get('selected.stonehearth:commands.commands'), filter_fn);
      commands.sort(function (a, b) {
         var aName = a.ordinal ? a.ordinal : 0;
         var bName = b.ordinal ? b.ordinal : 0;
         var n = bName - aName;
         return n;
      });
      return commands;
   }.property('selected.stonehearth:commands.commands')

});
