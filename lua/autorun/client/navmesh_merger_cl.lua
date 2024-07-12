local nextRecieve = 0
net.Receive( "navoptimizer_nag", function()
    if nextRecieve > CurTime() then return end
    nextRecieve = CurTime() + 5

    if system.HasFocus() then return end
    system.FlashWindow()

end )