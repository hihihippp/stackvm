function Workspace (rootElem, account) {
    if (!(this instanceof Workspace))
        return new Workspace(rootElem, account);
    var self = this;
    
    var leftPane = $('<div>')
        .attr('id','left-pane')
        .hide()
        .fadeIn(400);
    ;
    rootElem.append(leftPane);
    $('form#login').fadeOut(400);
    
    this.useVM = function (vmName) {
        leftPane.append($('<div>')
            .addClass('vm-desc')
            .click(function () {
                self.attach(vmName);
            })
            .append($('<div>').text(vmName))
        );
    };
    
    this.attach = function () {
        // 
    };
    
    account.vmList(function (vmList) {
        vmList.forEach(self.useVM);
    });
}
