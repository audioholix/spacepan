/* SpacePan V1.1

This is a basic spatial audio tool using source oriented vector based
delay and amplitude panning as well as basic room simulation.

This code was written using SC3.11 / OSX10.13.6
Dependencies: Quarks wslib, mathlib and SC3plugins package.

It is crucial to read the helpfile.
Check out the tutorial on youtube as well (way too long, just skip thru.. )

dominik.wegmann@tonmeister.de
www.sccode.org/audioholic


*/

(// ----- code starts here. set main parameters first! (soundcard, number i/o, loudspeakers, room...)
var sources, statsources, currpath, makeBusses, makeSynths, makeGUI, makeNodes;
var srcgroup, fxsgroup, mstrgroup, master, testsig, reverb, early, delay, aux, revbus, dlybus, auxbus, fxretbus, masterbus, tracklevel;
var newsrc, removesrc, editsrc, srcmute, srcsolo, srcon, srcstate, srclevel, makesnap, recallsnap, mirrorXYC;
var pos2pan, pos2point, rect2pos, pos2angle, pos2rect, pos2drive, autorota, autorand, saveprj, loadprj, gethelp, autorefreshview, cleanup;
var gui, guipoints, srcsize, btnsize, fdrsize, txtsize, clicked, selected, mousepoint, oldmspoint, mousedist, roomdim, roomscale, lspos, scolors, colors, fontsml, fontlrg, rotaspeedSpec, randspeedSpec, randrangeSpec, rotastepSpec, focusSpec;
var speedofsound = 343, autorefreshrate = 0.03, showlbl = true, showls = true, showroomsens = false, backgroundgradient = false, solostate = 0;
var masterout = 4, roomsens = 0.5, roomdamp = -12, roomfreq = 8000, xfade = 1, xfadetime = 2, xstep = 0.02;

// ----- server options
s = Server.local;
s.options.device = "Babyface Pro (71967432)"; //audio device.
s.options.numOutputBusChannels = 12; //n outputs. use "masterout" to offset
s.options.numInputBusChannels = 4; //n inputs
s.options.sampleRate = 48000;
s.newBusAllocators;
//CmdPeriod.doOnce({gui.win.close});

// ----- set room & loudspeakers
roomdim = 15; //virtual room size in meters (always square shape)
roomscale = roomdim/2; //factor to reduce divisions in some functions
lspos = [ //your real loudspeaker positions [x, y] You can offset, but be precise with speaker-to-speaker relation!
	[-2, 2], //!!!set arraysize of amps#[] and delays#[] in synthdefs "spacepan" & "staticsrc" to number of speakers!
	[0, 2.5],
	[2, 2],
	[2.5, 0],
	[2, -3],
	[-2, -3],
	[-2.5, 0]
];

lspos.size.do{arg i, it; lspos[i] = lspos[i].asPoint}; //convert pos to point array
//statpos.size.do{arg i, it; statpos[i] = statpos[i].asPoint};

currpath = PathName(thisProcess.nowExecutingPath).parentPath; //project path
sources = Dictionary.new; //create dict for sound sources
rotaspeedSpec = ControlSpec(0.4, 0.01, 'exp', 0.001, 0.1);
rotastepSpec = ControlSpec(0.01, 0.02, 'exp', 0.001, 0.015);
randspeedSpec = ControlSpec(3.0, 0.1, 'exp', 0.1, 1.0);
randrangeSpec = ControlSpec(0.1, roomscale/2, 'exp', 0.1, 1);
focusSpec = ControlSpec(0, 2, 'lin', 0.1);

gui = (); //the gui environment
guipoints = 800; //some gui settings...
srcsize = 15;
txtsize = Point(40, 24);
btnsize = Point(65, 24);
fdrsize = Point(135, 24);
fontlrg = Font("Helvetica", 18);
fontsml = Font("Helvetica", 13);
scolors = [ //source colors
	Color.new255(238, 238, 43), //yellow, default
	Color.new255(0, 230, 114), //green
	Color.new255(255, 182, 193), //lightpink
	Color.new255(110, 159, 247), //blue
	Color.new255(255, 165, 0) //orange
];

colors = [ //colors to use somehow
	Color.new255(245, 222, 179),
	Color.blue(0.7, 0.9)
];

// ----- init
s.waitForBoot({
	Routine.run({

		"\n--- busses ---".postln;
		makeBusses.value;
		s.sync;

		"\n--- synthdefs ---".postln;
		makeSynths.value;
		s.sync;

		"\n--- groups, fx and master ---".postln;
		makeNodes.value;
		s.sync;

		"\n--- draw the gui ---".postln;
		{makeGUI.value}.defer;
		s.sync;

		autorefreshview.start; //autorefresh spaceview
	});
});

makeBusses = { //create audio busses
	masterbus = Bus.audio(s, lspos.size);
	revbus = Bus.audio(s, lspos.size);
	dlybus = Bus.audio(s, lspos.size);
	auxbus = Bus.audio(s, 1);
	fxretbus = Bus.audio(s, 4);
	("Master Bus Index: "++masterbus.index).postln;
	("Reverb Bus Index: "++revbus.index).postln;
	("Delay Bus Index: "++dlybus.index).postln;
	("Aux Bus Index: "++auxbus.index).postln;
	("FX Return Bus Index: "++fxretbus.index).postln;
	("Sending default test signal on bus 100").postln;
};

makeNodes = {
	// ----- groups
	srcgroup = Group(s); //source
	fxsgroup = Group.after(srcgroup); //fx sends
	mstrgroup = Group.after(fxsgroup); //master

	// ----- test signal
	testsig = Synth("testsig", [\out, 100]);

	// ----- lousy nchannel reverb
	reverb = lspos.size.collect{arg it;
		Synth("reverb", [
			\in, revbus.index + it,
			\out, masterbus.index + it,
			\room, 0.5,
			\damp, 0.5*rrand(0.9, 1.1),
			\amp, 0.5
	], fxsgroup)};

	// ----- nchannel delay
	delay = lspos.size.collect{arg it;
		Synth("delay", [
			\in, dlybus.index+it,
			\out, masterbus.index+it,
			\dly, 0.25,
			\dcy, 2.0,
			\lpf, 4000,
			\hpf, 200,
			\amp, 0.5
	], fxsgroup)};

	// ----- master
	master = Synth("master", [\in, masterbus, \out, masterout, \amp, 1, \gate, 1], mstrgroup);

	// ----- source input metering
	tracklevel = Synth("tracklevel", addAction:'addToTail');

};

// ----- main gui window
makeGUI = {
	gui.win = Window(" SPACEPAN ", Rect(0, 0, 1040, 810).center_(Window.availableBounds.center), resizable: false, border: true).front;
	//gui.win.alwaysOnTop_(true).userCanClose_(true);
	gui.win.onClose = {cleanup.value};
	gui.win.view.background = Color.gray(0.2);

	// ----- subviews
	gui.srctop = View(gui.win, Rect(5, 5, 225, 40)).backColor_(Color.gray(0.85));
	gui.srctop.addFlowLayout(5@5, 5@5);

	gui.src = View(gui.win, Rect(5, 50, 225, 540)).backColor_(Color.gray(0.85)).enabled_(false);
	gui.src.addFlowLayout(5@5, 5@5);

	gui.opt = View(gui.win, Rect(5, 595, 225, 100)).backColor_(Color.gray(0.85));
	gui.opt.addFlowLayout(5@5, 5@5);

	gui.mstr = View(gui.win, Rect(5, 700, 225, 105)).backColor_(Color.gray(0.85));
	gui.mstr.addFlowLayout(5@5, 5@5);

	gui.fxpanel = Window("FX SETTINGS", Rect(0, 0, 285, 350),
		resizable: false, scroll: true).visible_(false).userCanClose_(false);
	gui.fxpanel.addFlowLayout(5@5, 5@5);

	gui.snaplist = Window("SNAPSHOTS", Rect(0, 0, 285, 450),
		resizable: false).visible_(false).userCanClose_(false);

	gui.meters = Window("METERING",
		Rect(0, 0, ServerMeterView.getWidth(0, s.options.numOutputBusChannels), ServerMeterView.height),
		resizable: false).visible_(false).userCanClose_(false);

	gui.space = UserView(gui.win, Rect(235, 5, guipoints, guipoints)).backColor_(Color.black);

	// ----- source panel top
	StaticText(gui.srctop, Point(70, 30)).string_("Source: ").font_(fontlrg);

	gui.srcID = StaticText(gui.srctop, Point(40, 28)).string_("0").font_(fontlrg).align_(\center);

	gui.srcPrev = Button(gui.srctop, Point(27, 27)).string_(" < ").font_(fontlrg)
	.action_({arg view;
		if(selected > 1) {
			selected = selected -1;
			editsrc.value(selected)};
	});

	gui.srcNext = Button(gui.srctop, Point(27, 27)).string_(" > ").font_(fontlrg)
	.action_({arg view;
		if (sources.keys.maxItem > selected){
			selected = selected +1;
			editsrc.value(selected)};
	});

	gui.srcAdd = Button(gui.srctop, Point(27, 27)).font_(fontlrg)
	.states_([[" + ", Color.black, Color.green(0.9)]])
	.action_({arg view; newsrc.value});


	// ----- source edit panel
	StaticText(gui.src, txtsize).string_("Label").font_(fontsml);
	gui.srcLabel = TextField(gui.src, btnsize).string_("Name").font_(fontsml);

	gui.srcGrp = PopUpMenu(gui.src, btnsize).
	items_(["NoGrp", "Grp1", "Grp2", "Grp3", "Grp4"]).font_(fontsml);

	StaticText(gui.src, txtsize).string_("Input").font_(fontsml);
	gui.srcInput = NumberBox(gui.src, btnsize).step_(1).value_(0).font_(fontsml);

	gui.srcMeter = LevelIndicator(gui.src, btnsize).style_(\led).stepWidth_(1).warning_(0.8).critical_(0.95);

	StaticText(gui.src, txtsize).string_("").font_(fontsml);
	gui.srcSolo = Button(gui.src, btnsize).font_(fontsml)
	.states_([["Solo", Color.black, Color.gray(0.9)], ["Solo", Color.black, Color.yellow]]);

	gui.srcMute = Button(gui.src, btnsize).font_(fontsml)
	.states_([ ["Mute", Color.black, Color.red ], ["Mute", Color.black, Color.gray(0.9)] ])
	.value_(1);

	StaticText(gui.src, txtsize).string_("Level").font_(fontsml);
	gui.srcVol = Slider(gui.src, fdrsize);
	gui.srcVolnum = StaticText(gui.src, Point(30,24)).string_("-inf").font_(fontsml);

	StaticText(gui.src, txtsize).string_("Focus").font_(fontsml);
	gui.srcFocus = Slider(gui.src, fdrsize).step_(0.1);
	gui.srcFocusnum = StaticText(gui.src, Point(30,24)).string_("0.0").font_(fontsml);

	StaticText(gui.src, txtsize).string_("Mode").font_(fontsml);
	StaticText(gui.src, Point(115,24)).string_("Apply Delay").font_(fontsml);
	gui.srcPanmode = CheckBox(gui.src, Point(24,24)).value_(0);

	StaticText(gui.src, txtsize).string_("").font_(fontsml);
	StaticText(gui.src, Point(115,24)).string_("Apply Room FX").font_(fontsml);
	gui.srcRoom = CheckBox(gui.src, Point(24,24)).value_(1);

	// ----- fx sends
	StaticText(gui.src, txtsize).string_("Rev").font_(fontsml);
	gui.srcRev = Slider(gui.src, fdrsize);
	gui.srcRevnum = StaticText(gui.src, Point(30,24)).string_("-inf").font_(fontsml);

	StaticText(gui.src, txtsize).string_("Dly").font_(fontsml);
	gui.srcDly = Slider(gui.src, fdrsize);
	gui.srcDlynum = StaticText(gui.src, Point(30,24)).string_("-inf").font_(fontsml);

	StaticText(gui.src, txtsize).string_("Aux").font_(fontsml);
	gui.srcAux = Slider(gui.src, fdrsize).enabled_(false);
	gui.srcAuxnum = StaticText(gui.src, Point(30,24)).string_("-inf").font_(fontsml);

	// ----- automation (rota/rand)
	StaticText(gui.src, txtsize).string_("Rota").font_(fontsml);
	gui.srcRota = Button(gui.src,Point(35,24))
	.states_([["ON", Color.black, Color.gray(0.9)], ["ON", Color.black, Color.cyan]]).font_(fontsml);

	gui.srcRotaDir = PopUpMenu(gui.src, Point(95, 24)).items_(["Clockwise","Anticlock"]).font_(fontsml);

	StaticText(gui.src, txtsize).string_("Speed").font_(fontsml);
	gui.srcRotaSpeed = Slider(gui.src, fdrsize);
	gui.srcRotaSpeedString = StaticText(gui.src, Point(30,24)).string_("0.0").font_(fontsml);

	StaticText(gui.src, txtsize).string_("Rand").font_(fontsml);
	gui.srcRand = Button(gui.src,Point(35,24)).font_(fontsml)
	.states_([["ON", Color.black, Color.gray(0.9)], ["ON", Color.black, Color.cyan]]).font_(fontsml);

	gui.src.decorator.nextLine;

	StaticText(gui.src, txtsize).string_("Step").font_(fontsml);
	gui.srcRandRange = Slider(gui.src, fdrsize);
	gui.srcRandRangeString = StaticText(gui.src, Point(30,24)).string_("0.0").font_(fontsml);

	StaticText(gui.src, txtsize).string_("Speed").font_(fontsml);
	gui.srcRandSpeed = Slider(gui.src, fdrsize);
	gui.srcRandSpeedString = StaticText(gui.src, Point(30,24)).string_("0.0").font_(fontsml);

	// ----- position mirroring
	StaticText(gui.src, txtsize).string_("Mirror").font_(fontsml);

	gui.srcMrX = Button(gui.src, Point(41,24)).states_([[" x "]]).font_(fontsml);
	//.action_({arg view; mirrorXYC.value(1)});

	gui.srcMrY = Button(gui.src, Point(41,24)).states_([[" y "]]).font_(fontsml);
	//.action_({arg view; mirrorXYC.value(2)});

	gui.srcMrC = Button(gui.src, Point(41,24)).states_([[" c "]]).font_(fontsml);
	//.action_({arg view; mirrorXYC.value(3)});

	// ----- show src position
	StaticText(gui.src, txtsize).string_("Pos").font_(fontsml);
	gui.srcposX = StaticText(gui.src, btnsize).string_("X: 0.0 m").font_(fontsml);
	gui.srcposY = StaticText(gui.src, btnsize).string_("Y: 0.0 m").font_(fontsml);
	StaticText(gui.src, txtsize).string_("").font_(fontsml);
	gui.srcposDeg = StaticText(gui.src, btnsize).string_("A: 0.0 °").font_(fontsml);
	gui.srcposDist = StaticText(gui.src, btnsize).string_("D: 0.0 m").font_(fontsml);


	// ----- duplicate/remove
	/*gui.srcCopy = Button(gui.src, Point(105,24))
	.string_("Duplicate Src").font_(fontsml)
	.action_({arg view; copysrc.value(selected)});

	gui.srcRemove = Button(gui.src, Point(105,24))
	.string_("Remove Src").font_(fontsml)
	.action_({arg view; removesrc.value});*/


	// ----- space view for source positioning
	gui.space.drawFunc_({ arg view;
		var bounds = view.bounds.moveTo(0,0);

		// background:
		if(backgroundgradient){
			Pen.addOval(bounds);
			Pen.fillRadialGradient(bounds.center, bounds.center,0, guipoints/2, colors[1], Color.black);
		};

		// cross at center:
		Pen.width = 1;
		Pen.strokeColor = colors[0];
		Pen.line(Point(guipoints/2 - 15, guipoints/2), Point(guipoints/2 + 15, guipoints/2));
		Pen.line(Point(guipoints/2, guipoints/2 - 15), Point(guipoints/2, guipoints/2 + 15));
		Pen.stroke;

		// dim:
		/*Pen.stringAtPoint("-y", Point(guipoints/2, guipoints-20), color:colors[0]);
		Pen.stringAtPoint("+x", Point(guipoints-20, guipoints/2), color:colors[0]);
		Pen.stringAtPoint("-x", Point(0, guipoints/2), color:colors[0]);
		Pen.stringAtPoint("+y", Point(guipoints/2, 0), color:colors[0]);*/


		// roomfx threshold:
		if(showroomsens){
			Pen.width = 1;
			Pen.strokeColor = colors[0];
			Pen.strokeOval(Rect.aboutPoint(pos2point.value(Point(0, 0)), roomsens*guipoints/2, roomsens*guipoints/2));
		};

		// loudspeakers:
		if(showls){
			Pen.fillColor = colors[0];
			lspos.size.do{ arg i;
				Pen.fillRect(Rect.aboutPoint(pos2point.value(lspos[i]), 8, 8));
				Pen.stringCenteredIn((i+1).asString, Rect.aboutPoint(pos2point.value(lspos[i]), 8, 8), Font(size: 10), Color.black);
			};
		};
		// sources:
		if(sources.size > 0){
			sources.pairsDo { arg key, src, i;
				Pen.fillColor = src[\state].if( { scolors[src[\grpid]] }, { Color.grey(0.7) } );
				Pen.fillOval(src[\rect]);
				if(showlbl){
					Pen.stringAtPoint(src[\label], src[\rect].rightBottom - Point(4, 4));
				};
				Pen.fillColor = Color.black;
				Pen.stringCenteredIn(src[\id].asString, src[\rect]);

			};
		};
		// source marker:
		if(selected.notNil) {
			Pen.width = 3;
			Pen.strokeColor = Color.red;
			Pen.strokeOval(sources[selected][\rect]);
		};

	})
	// action when source is clicked:
	.mouseDownAction_({ arg view, x, y, modifiers, buttonNumber, clickCount;
		mousepoint = Point(x,y);
		oldmspoint = mousepoint;
		clicked = nil;
		sources.pairsDo { arg key, src, i;  if (src[\rect].containsPoint(mousepoint)) { clicked = key } };
		if(clicked.notNil) {
			mousedist = (mousepoint - (sources[clicked][\rect].origin));
			if(clicked != selected) {
				selected = clicked;
				editsrc.value(selected);
			};

			if(sources[clicked][\grpid] > 0 && modifiers.isShift){
				sources.pairsDo{ arg key, src, i;
					if(src[\grpid] == sources[clicked][\grpid]){
						if(modifiers.isAlt){ srcstate.value(key) };
						if(modifiers.isCtrl){ srcsolo.value(key) };
					};
				};
				editsrc.value(clicked);
			}{
				if(modifiers.isAlt) { srcstate.value(clicked); editsrc.value(clicked) };
				if(modifiers.isCtrl) { srcsolo.value(clicked); editsrc.value(clicked) };
			};
		};
	})
	// action when source is moved:
	.mouseMoveAction_({ arg view, x, y, modifiers;
		var bounds = view.bounds.moveTo(0,0);
		if (clicked.notNil){
			mousepoint = Point(x.clip(bounds.left, bounds.right), y.clip(bounds.top, bounds.bottom));

			if(sources[clicked][\grpid] > 0 && modifiers.isShift){ //move group

				sources.pairsDo{ arg key, src, i;

					if(src[\grpid] == sources[clicked][\grpid]){
						src[\rect] = src[\rect].translate(mousepoint - oldmspoint);
						rect2pos.value(key);
						pos2drive.value(key);
					};
				};

				oldmspoint = mousepoint;
			}{ //move single source
				sources[clicked][\rect] = sources[clicked][\rect].moveToPoint(mousepoint - mousedist);
				rect2pos.value(clicked);
				pos2drive.value(clicked);
			};

			view.action.value(this, x, y, modifiers);
		};
	})
	// action when mousebutton is released:
	.mouseUpAction_({ arg view, x, y, modifiers;
		clicked = nil;
	});
	// end of spaceview

	// ----- option panel
	gui.sessnMenu = Menu(
		MenuAction("Load", { loadprj.value }),
		MenuAction("Save", { saveprj.value }),
		MenuAction("Help", { gethelp.value }),
		MenuAction("Quit", { gui.win.close }),
	);

	gui.optnMenu = Menu(
		MenuAction("Show Loudspeakers")
		.checkable_(true)
		.checked_(showls)
		.action_({arg a, checked;
			if(checked){
				showls = true;
			}{
				showls = false;
			};
		}),

		MenuAction("Show Labels")
		.checkable_(true)
		.checked_(showlbl)
		.action_({arg a, checked;
			if(checked){
				showlbl = true;
			}{
				showlbl = false;
			};
		}),

		MenuAction("Show Roomsens")
		.checkable_(true)
		.checked_(showroomsens)
		.action_({arg a, checked;
			if(checked){
				showroomsens = true;
			}{
				showroomsens = false;
			};
		}),

		MenuAction("Gradient Space")
		.checkable_(true)
		.checked_(backgroundgradient)
		.action_({arg a, checked;
			if(checked){
				backgroundgradient = true;
			}{
				backgroundgradient = false;
			};
		});

	);

	gui.sessn = Button(gui.opt, Point(105, 24)).string_("Session..").font_(fontsml)
	.action_({arg view;
		gui.sessnMenu.front;
	});

	gui.optn = Button(gui.opt, Point(105, 24)).string_("View..").font_(fontsml)
	.action_({arg view;
		gui.optnMenu.front;
	});

	gui.showsnaplist = Button(gui.opt, Point(105, 24)).string_("Snapshots").font_(fontsml)
	.action_({arg view;
		if(gui.snaplist.visible == false) {
			gui.snaplist.visible = true;
			gui.snaplist.bounds = gui.snaplist.bounds.moveToPoint(Point(gui.win.bounds.rightBottom.x,
				gui.win.bounds.rightBottom.y - gui.snaplist.bounds.extent.y));
		}{
			gui.snaplist.visible = false };
	});

	gui.showsettings = Button(gui.opt, Point(105, 24)).string_("FX Settings").font_(fontsml)
	.action_({arg view;
		if(gui.fxpanel.visible == false) {
			gui.fxpanel.visible = true;
			gui.fxpanel.bounds = gui.fxpanel.bounds.moveToPoint(gui.win.bounds.rightTop);
		}{
			gui.fxpanel.visible = false };
	});

	gui.showmeters = Button(gui.opt, Point(105, 24)).string_("Out Meters").font_(fontsml)
	.action_({arg view;
		if(gui.meters.visible == false) {
			m = ServerMeterView.new(s, gui.meters, Point(0,0), 0, s.options.numOutputBusChannels);
			gui.meters.visible = true;
			gui.meters.bounds = gui.meters.bounds.moveToPoint(gui.win.bounds.rightTop);
		}{
			gui.meters.visible = false;
			m.free;
		};

	});

	gui.na2 = Button(gui.opt, Point(105, 24)).string_("n/a").font_(fontsml)
	.action_({arg view;
	});


	// ----- master
	StaticText(gui.mstr, txtsize).string_("Master").font_(fontsml);
	gui.mstrlevel = Slider(gui.mstr, fdrsize).value_(1)
	.action_({arg view;
		master.set(\amp, view.value);
		gui.mstrlevelnum.string_(view.value.ampdb.round(0.1).asString);
	});

	gui.mstrlevelnum = StaticText(gui.mstr, Point(30, 24)).string_("0").font_(fontsml);

	StaticText(gui.mstr, txtsize).string_("Out").font_(fontsml);
	gui.masterBus = NumberBox(gui.mstr, btnsize).value_(masterout).font_(fontsml).step_(1)
	.action_({arg view;
		view.value = view.value.clip(0, 127);
		master.set(\out, view.value);
	});

	gui.mstrMute = Button(gui.mstr, btnsize).font_(fontsml)
	.states_([ ["Mute", Color.black, Color.red ], ["Mute", Color.black, Color.gray(0.9)] ])
	.value_(1)
	.action_({arg view;
		master.set(\gate, view.value);
	});

	// ----- fx settings window
	StaticText(gui.fxpanel, 260@20).string_("::: GENERAL :::").align_(\center);

	gui.roomsens = EZSlider.new(gui.fxpanel, 260@20 ,"Rm Sens",ControlSpec(0.1, 0.9,\lin, 0.01, roomsens),
		{arg view;
			roomsens = view.value;
			if(sources.size > 0){
				sources.pairsDo({arg key, src, i;
					src[\node].set(\roomsens, view.value);
				});
			};
	});

	gui.roomfreq = EZSlider.new(gui.fxpanel, 260@20 ,"Rm LPF",ControlSpec(200, 12000, 'exp', 1, roomfreq),
		{arg view;
			roomfreq = view.value;
			if(sources.size > 0){
				sources.pairsDo({arg key, src, i;
					src[\node].set(\roomfreq, view.value);
				});
			};
	});

	gui.roomdamp = EZSlider.new(gui.fxpanel, 260@20 ,"Rm Damp",ControlSpec(-3, -24, \lin, 1, roomdamp),
		{arg view;
			roomdamp = view.value;
			if(sources.size > 0){
				sources.pairsDo({arg key, src, i;
					src[\node].set(\roomdamp, view.value.dbamp);
				});
			};
	});

	// ----- reverb
	StaticText(gui.fxpanel, 260@20).string_("::: REVERB :::").align_(\center);

	gui.revlevel = EZSlider.new(gui.fxpanel, 260@20 ,"Rev Level",ControlSpec(-60, 0, \lin, 1, -6),
		{arg view;
			reverb.do{arg it;
				it.set(\amp, view.value.dbamp)
			}
	});

	gui.revtime = EZSlider.new(gui.fxpanel, 260@20 ,"Size",ControlSpec(0.2, 1.0, \lin, 0.01, 0.5),
		{arg view;
			reverb.do{arg it;
				it.set(\room, view.value)
			}
	});

	gui.revlf = EZSlider.new(gui.fxpanel, 260@20 ,"Damp",ControlSpec(0.2, 0.8, \lin, 0.01, 0.5),
		{arg view;
			reverb.do{arg it;
				it.set(\damp, view.value * rrand(0.9, 1.1))
			}
	});

	/*gui.revhf = EZSlider.new(gui.fxpanel, 260@20 ,"HF Ratio",ControlSpec(0.5, 1.5, \lin, 0.1, 1.0),
		{arg view;
			reverb.do{arg it;
				it.set(\hfratio, view.value)
			}
	});*/

	// ----- delay
	StaticText(gui.fxpanel, 260@20).string_("::: DELAY :::").align_(\center);

	gui.dlylevel = EZSlider.new(gui.fxpanel, 260@20,"Dly Level",ControlSpec(-60, 0, \lin, 1, -6),
		{arg view;
			delay.do{arg it;
				it.set(\amp, view.value.dbamp)
			}
	});

	gui.dly = EZSlider.new(gui.fxpanel, 260@20,"Dly T",ControlSpec(0.1, 1.0, \lin, 0.01, 0.25),
		{arg view;
			delay.do{arg it;
				it.set(\dly, view.value)
			}
	});

	gui.dcy = EZSlider.new(gui.fxpanel, 260@20,"Dcy T",ControlSpec(1.0, 5.0, \lin, 0.1, 2.0),
		{arg view;
			delay.do{arg it;
				it.set(\dcy, view.value)
			}
	});

	gui.dlyfilt = EZRanger.new(gui.fxpanel, 260@20,"Filter",\freq, initVal: [200,4000])
	.action_({arg view;
		delay.do{arg it;
			it.set(\hpf, view.value[0]*rrand(0.95, 1.05));
			it.set(\lpf, view.value[1]*rrand(0.95, 1.05));
		}
	});


	// ---- snapshot window
	gui.snapshots = ListView(gui.snaplist, Rect(5, 5, 275, 320))
	.background_(Color.gray(0.9))
	.font_(fontsml)
	.hiliteColor_(Color.yellow(alpha: 0.6))
	.selectedStringColor_(Color.black)
	.items_([ ])
	.selectionMode_(\single)
	.action_({arg view;
		//recallsnap.value;
	});

	gui.activeSnap = StaticText(gui.snaplist, Rect(5, gui.snapshots.bounds.leftBottom.y+5, gui.snapshots.bounds.width, 35))
	.backColor_(Color.white)
	.string_(" >> ")
	.font_(fontlrg);

	gui.deleteSnap = Button(gui.snaplist, Rect(5, gui.snapshots.bounds.leftBottom.y+45, 65, 35)).string_("Delete")
	.action_({arg view;
		if(gui.snapshots.items.size > 0){ gui.snapshots.items = gui.snapshots.items.removing(gui.snapshots.item) };
	});

	gui.makeSnap = Button(gui.snaplist, Rect(75, gui.snapshots.bounds.leftBottom.y+45, 65, 35)).string_("Make")
	.action_({arg view;
		makesnap.value;
	});

	gui.recallSnap = Button(gui.snaplist, Rect(145, gui.snapshots.bounds.leftBottom.y+45, 65, 35)).string_("Recall")
	.action_({arg view;
		recallsnap.value;
		gui.activeSnap.string = " >> "++gui.snapshots.item;
	});

	gui.nextSnap = Button(gui.snaplist, Rect(215, gui.snapshots.bounds.leftBottom.y+45, 65, 35)).string_("Next")
	.action_({arg view;
		gui.snapshots.value = (gui.snapshots.value + 1).clip(0, gui.snapshots.items.maxIndex);
		recallsnap.value;
		gui.activeSnap.string = " >> "++gui.snapshots.item;
	});

	gui.xactive = Button(gui.snaplist, Rect(5, gui.snapshots.bounds.leftBottom.y+85, 65, 25))
	.states_([ ["X [sec]", Color.black, Color.grey(0.9) ], ["X [sec]", Color.black, Color.cyan] ])
	.value_(1)
	.action_({arg view; xfade = view.value});

	gui.xtime = NumberBox(gui.snaplist, Rect(75, gui.snapshots.bounds.leftBottom.y+85, 30, 25))
	.value_(xfadetime)
	.align_(\center)
	.action_({arg view; view.value = view.value.clip(1, 10); xfadetime = view.value });

};// ----- end of GUI


// ----- create new source
newsrc = { var id, src, point;

	if(sources.size < 1){
		gui.src.enabled_(true);
		id = 1}{
		id = sources.keys.maxItem + 1};

	src = Dictionary[
		\id -> id,
		\label -> id.asString,
		\inbus -> 100,
		\rect -> nil,
		\pos -> Point((roomscale/2).rand2, 0).round(0.1),
		\grpid -> 0,
		\room -> 1,
		\dodelays -> 0,
		\focus -> 0,
		\amp -> 0,
		\solo -> false,
		\rotastate -> false,
		\rota -> nil,
		\rotaspeed -> 0.04,
		\rotadir -> -1,
		\randstate -> false,
		\rand -> nil,
		\randrange -> 1,
		\randspeed -> 1,
		\aux -> 0,
		\rev -> 1,
		\dly -> 0,
		\node -> nil,
		\state -> true
	];

	src[\rect] = pos2rect.value(src[\pos]);
	sources.add(id -> src);
	selected = id;
	editsrc.value(selected);
	srcon.value(selected);
};

// ----- start the src processing synth
srcon = { arg id;
	var src;
	src = sources[id];

	src[\node] = Synth("spacepan", [
		\inbus, src[\inbus],
		\out, masterbus,
		\revbus, revbus,
		\dlybus, dlybus,
		\auxbus, auxbus,
		\amp, src[\amp],
		\dodelays, src[\dodelays],
		\rev, src[\rev],
		\dly, src[\dly],
		\aux, src[\aux],
		\room, src[\room],
		\roomsens, roomsens,
		\roomdamp, roomdamp.dbamp,
		\roomfreq, roomfreq
	], srcgroup);
	pos2drive.value(id);
};


// ----- edit selected source settings
editsrc = {arg selected;
	var src;
	src = sources[selected];
	srclevel.value;
	tracklevel.set(\inbus, src[\inbus]);

	gui.srcID
	.string_(src[\id].asString);

	gui.srcLabel
	.value_(src[\label])
	.action_({arg view;
		src[\label]	= view.value[..7];
	});

	gui.srcGrp
	.background_(scolors[src[\grpid]])
	.value_(src[\grpid])
	.action_({ arg view;
		view.background = scolors[view.value];
		src[\grpid] = view.value;
	});

	gui.srcInput
	.value_(src[\inbus])
	.action_({arg view;
		src[\inbus] = view.value;
		src[\node].set(\inbus, src[\inbus]);
		tracklevel.set(\inbus, src[\inbus]);
	});

	gui.srcVol
	.value_(src[\amp])
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					sc[\amp] = view.value;
					sc[\node].set(\amp, sc[\amp]);
				};
			};
		}{
			src[\amp] = view.value;
			src[\node].set(\amp, src[\amp]);
		};

		gui.srcVolnum.string = src[\amp].ampdb.round(0.1).asString;

	});

	gui.srcVolnum
	.string_(src[\amp].ampdb.round(0.1).asString);

	gui.srcMute
	.value_(src[\state])
	.action_({arg view, mod;
		if(src[\grpid] > 0 && mod.isShift){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					srcstate.value(sc[\id])
				};
			};
		}{ srcstate.value(selected) }
	});

	gui.srcSolo
	.value_(src[\solo])
	.action_({arg view, mod;
		if(src[\grpid] > 0 && mod.isShift){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					srcsolo.value(sc[\id])
				};
			};
		}{ srcsolo.value(selected) }

	});

	gui.srcPanmode
	.value_(src[\dodelays])
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					sc[\dodelays] = view.value.asInteger;
					sc[\node].set(\dodelays, sc[\dodelays])
				};
			};
		}{
			src[\dodelays] = view.value.asInteger;
			src[\node].set(\dodelays, src[\dodelays])
		};
	});

	gui.srcFocus
	.value_(focusSpec.unmap(src[\focus]))
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					sc[\focus] = focusSpec.map(view.value);
					pos2drive.value(sc[\id]);
				};
			};
		}{
			src[\focus] = focusSpec.map(view.value);
			pos2drive.value(selected);
		};

		gui.srcFocusnum.string = view.value.asString;
	});

	gui.srcFocusnum.string = focusSpec.unmap(src[\focus]).asString;

	gui.srcRoom
	.value_(src[\room])
	.action_({arg view;
		src[\room] = view.value;
		src[\node].set(\room, src[\room]);
	});

	gui.srcRev
	.value_(src[\rev])
	.action_({arg view;
		src[\rev] = view.value;
		gui.srcRevnum.string = src[\rev].ampdb.round(0.1).asString;
		src[\node].set(\rev, src[\rev]);
	});

	gui.srcRevnum.string_(src[\rev].ampdb.round(0.1).asString);

	gui.srcDly
	.value_(src[\dly])
	.action_({arg view;
		src[\dly] = view.value;
		gui.srcDlynum.string = src[\dly].ampdb.round(0.1).asString;
		src[\node].set(\dly, src[\dly]);
	});

	gui.srcDlynum.string_(src[\dly].ampdb.round(0.1).asString);

	gui.srcAux
	.value_(src[\aux])
	.action_({arg view;
		src[\aux] = view.value;
		gui.srcAuxnum.string = src[\aux].ampdb.round(0.1).asString;
		src[\node].set(\aux, src[\aux]);
	});

	gui.srcAuxnum.string_(src[\aux].ampdb.round(0.1).asString);

	gui.srcRota
	.value_(src[\rotastate].asInteger)
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					sc[\rotastate] = view.value.asBoolean;
					if(sc[\randstate]){
						sc[\randstate] = false;
						autorand.value(key);
						gui.srcRand.value_(0);
					};
					autorota.value(key);
				};
			};
		}{
			src[\rotastate] = view.value.asBoolean;
			if(src[\randstate]){
				gui.srcRand.value_(0);
				src[\randstate] = false;
				autorand.value(selected);
			};
			autorota.value(selected);
		};
	});

	gui.srcRotaSpeed
	.value_(rotaspeedSpec.unmap(src[\rotaspeed]))
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					sc[\rotaspeed] = rotaspeedSpec.map(view.value);
				};
			};
		}{
			src[\rotaspeed] = rotaspeedSpec.map(view.value);
		};
		gui.srcRotaSpeedString.string = view.value.round(0.01).asString;
	});

	gui.srcRotaSpeedString.string = gui.srcRotaSpeed.value.round(0.01).asString;

	gui.srcRotaDir
	.value_(src[\rotadir].linlin(-1, 1, 0, 1))
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					sc[\rotadir] = view.value.linlin(0, 1, -1, 1);
				};
			};
		}{
			src[\rotadir] = view.value.linlin(0, 1, -1, 1);
		};
	});

	gui.srcRand
	.value_(src[\randstate].asInteger)
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					sc[\randstate] = view.value.asBoolean;
					if(sc[\rotastate]){
						sc[\rotastate] = false;
						autorota.value(key);
						gui.srcRota.value_(0);
					};
					autorand.value(key);
				};
			};
		}{
			src[\randstate] = view.value.asBoolean;
			if(src[\rotastate]){
				gui.srcRota.value_(0);
				src[\rotastate] = false;
				autorota.value(selected);
			};
			autorand.value(selected);
		};
	});

	gui.srcRandRange
	.value_(randrangeSpec.unmap(src[\randrange]))
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					sc[\randrange] = randrangeSpec.map(view.value);
				};
			};
		}{
			src[\randrange] = randrangeSpec.map(view.value);
		};
		gui.srcRandRangeString.string = view.value.round(0.01).asString;
	});

	gui.srcRandRangeString.string = gui.srcRandRange.value.round(0.01).asString;

	gui.srcRandSpeed
	.value_(randspeedSpec.unmap(src[\randspeed]))
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					sc[\randspeed] = randspeedSpec.map(view.value);
				};
			};
		}{
			src[\randspeed] = randspeedSpec.map(view.value);
		};
		gui.srcRandSpeedString.string = view.value.round(0.01).asString;
	});

	gui.srcRandSpeedString.string = gui.srcRandSpeed.value.round(0.01).asString;

	gui.srcMrX
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					mirrorXYC.value(sc[\id], 2);
				};
			};
		}{ mirrorXYC.value(selected, 2) };
	});

	gui.srcMrY
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					mirrorXYC.value(sc[\id], 1);
				};
			};
		}{ mirrorXYC.value(selected, 1) };
	});

	gui.srcMrC
	.action_({arg view;
		if(src[\grpid] > 0){
			sources.pairsDo{arg key, sc, i;
				if(sc[\grpid] == src[\grpid]){
					mirrorXYC.value(sc[\id], 3);
				};
			};
		}{ mirrorXYC.value(selected, 3) };
	});
};

// ----- mute source
srcstate = {arg id;
	var src;
	src = sources[id];
	if(src[\state]){
		src[\node].set(\gate, 0); src[\state] = false} {
		src[\node].set(\gate, 1); src[\state] = true };
};

// ----- solo source
srcsolo = {arg id;
	if(sources[id][\solo] == false){
		sources[id][\solo] = true;
		solostate = solostate +1;
		("!!! SOLO SOURCE "++id.asString).postln;
	}{
		sources[id][\solo] = false;
		solostate = solostate -1;
	};

	if(solostate > 0){
		sources.do{arg src;
			if(src[\solo] == true && src[\state] == true){
				src[\node].set(\gate, 1)
			}{ src[\node].set(\gate, 0) };
		};
	}{
		sources.do{arg src;
			if(src[\state] == true){
				src[\node].set(\gate, 1)
			}
		};
		("!!! SOLO OFF").postln;
	};

};

// ----- mirror source pos
mirrorXYC = {arg id, mode;
	if(mode == 1){sources[id][\pos] = sources[id][\pos].mirrorX};
	if(mode == 2){sources[id][\pos] = sources[id][\pos].mirrorY};
	if(mode == 3){sources[id][\pos] = sources[id][\pos].mirrorO};
	sources[id][\rect] = pos2rect.value(sources[id][\pos]);
	pos2drive.value(id);
};

// ----- update spacepan synth according to src gui position
pos2drive = {arg id;
	var src, dists, distance, amps, delays, pan;
	src = sources[id];

	//s.bind{
	dists = lspos.collect{arg i; src[\pos].dist(i).clip(0.1, roomdim)}; //clip dist to prevent div by zero
	delays = dists / speedofsound; //delays src->ls
	amps = dists.minItem / dists; //amp factors based on dist
	amps = amps.lincurve(amps.minItem, 1, 0, 1, src[\focus]); //focus windowing
	amps = amps / amps.squared.sum.sqrt; //equal power

	distance = src[\pos].rho / roomscale; //distance for roomfx
	//pan = pos2pan.value(src[\pos]); //4ch fx send pan

	//s.sync;
	src[\node].set(
		\delays, delays,
		\amps, amps,
		\distance, distance,
		//\pan, pan,
		\fxdlycomp, delays.minItem
	)
	//}
};

// ----- convert position to pan
// pos2pan = {arg pos;
// 	[pos.x.linlin(roomscale.neg, roomscale, fxpan.neg, fxpan), pos.y.linlin(roomscale.neg, roomscale, fxpan.neg, fxpan)];
// };

// ----- convert meters to pixels
pos2point = {arg pos;
	Point(pos.x.linlin(roomscale.neg, roomscale, 0, guipoints),
		pos.y.linlin(roomscale.neg, roomscale, guipoints, 0)).round(1.0);
};

// ----- calculate rect for spacegui
pos2rect = {arg pos;
	Rect.aboutPoint(pos2point.value(pos), srcsize, srcsize);
};

// ----- convert pixels to meters
rect2pos = {arg id;
	var src = sources[id];
	p = src[\rect].center;
	src[\pos] = (Point(p.x.linlin(0, guipoints, roomscale.neg, roomscale),
		p.y.linlin(0, guipoints, roomscale, roomscale.neg))).round(0.01);
};

// ----- convert pos to normalized degrees (-180..+180)
pos2angle = {arg pos;
	pos = pos.rotate(-0.5pi);
	pos.theta.raddeg.neg.round(0.1);
};

// ----- osc function to feed src levelmeter
srclevel = {
	OSCFunc({arg msg;
		{
			gui.srcMeter.value = msg[3].ampdb.linlin(-60, 0, 0, 1);
		}.defer;
	},'/level', s.addr);
};

// ----- automation: rotation
autorota = {arg id;
	var src = sources[id];
	if(src[\rotastate]){
		src[\rota] = Task({
			inf.do({arg i;
				{src[\pos] = src[\pos].rotate(rotastepSpec.map(rotaspeedSpec.unmap(src[\rotaspeed])) * src[\rotadir]);
					//src[\pos] = src[\pos].rotate(0.015 * src[\rotadir]);
					pos2drive.value(src[\id]);
					src[\rect] = pos2rect.value(src[\pos]);
				}.defer;
				(src[\rotaspeed]).wait;
			});
		}).start
	}{
		src[\rota].stop;
	};
};

// ----- automation: random walk
autorand = {arg id;
	var src = sources[id];
	if(src[\randstate]){
		src[\rand] = Task({
			inf.do({arg i;
				{src[\pos] = (src[\pos].translate(Point(src[\randrange].rand2,
					src[\randrange].rand2).round(0.01))).clip(roomscale.neg, roomscale);
					src[\rect] = pos2rect.value(src[\pos]);
					pos2drive.value(src[\id]);
				}.defer;
				(src[\randspeed]).wait;
			});
		}).start
	}{
		src[\rand].stop;
	};

};

// ----- autorefresh gui
autorefreshview = Task({
	loop {
		{ gui.space.refresh;
			if(selected.notNil){
				gui.srcposX.string_("X: "++sources[selected][\pos].x.round(0.01)++" m");
				gui.srcposY.string_("Y: "++sources[selected][\pos].y.round(0.01)++" m");
				gui.srcposDeg.string_("A: "++pos2angle.value(sources[selected][\pos])++" °");
				gui.srcposDist.string_("D: "++sources[selected][\pos].rho.round(0.01)++" m");
			};
		}.defer;
		autorefreshrate.wait;
	}
});

// ----- remove src
removesrc = {arg id;
	var src;
	if(sources.size > 0){
		src = sources[id];
		if(src[\rotastate]){src[\rota].stop};
		if(src[\randstate]){src[\rand].stop};
		if(src[\state]){src[\state] = false};
		src[\node].free;
		sources.removeAt(id);
	};
};

// ----- make snapshot
makesnap = {
	var path, stamp, array, filename, file;
	path = currpath++"Snapshots/";
	stamp = Date.getDate.format("%d%m%y_%H%M%S");
	filename = "Snapshot_"++stamp;
	file = File(path ++ filename ++".txt", "w");
	sources.pairsDo{arg i; array = array.add([sources[i][\id], sources[i][\pos]])};
	file.write(array.asCompileString);
	file.close;
	{gui.snapshots.items = gui.snapshots.items.add(filename)}.defer;

};

// ----- recall snapshot
recallsnap = {arg view;
	var path, file, filename, array, steps, env;
	path = currpath++"Snapshots/";
	filename = gui.snapshots.item;
	steps = (xfadetime/xstep).asInteger;

	sources.do{ arg src;
		if(src[\rotastate]){ src[\rota].stop; src[\rotastate] = false };
		if(src[\randstate]){ src[\rand].stop; src[\randstate] = false };
		editsrc.value(selected);
	};
	{
		file = File(path ++ filename ++".txt", "r");
		array = file.readAllString.interpret;

		if(xfade == 0){
			sources.do{arg src, i;
				src[\pos] = array[i][1];
				src[\rect] = pos2rect.value(src[\pos]);
				pos2drive.value(src[\id]);
			};
		}{
			{
				sources.do{arg src, i;
					env = env.add(Env.new(
						[src[\pos].asArray,
							array[i][1].asArray],
						[xfadetime]).discretize(steps)
					);
				};

				sources.do{arg src, it;
					Task({
						steps.do({arg i;
							{
								src[\pos].x = env[it][0][i];
								src[\pos].y = env[it][1][i];
								src[\rect] = pos2rect.value(src[\pos]);
								pos2drive.value(src[\id]);
							}.defer;
							xstep.wait;
						});
					}).start;
				};
			}.defer;
		};
	}.defer;
};

// ----- save current session
saveprj = { var array, snaps, fxparas, file;

		Dialog.savePanel( { arg path;
			file = File(path ++ ".txt", "w");
			fxparas = [
				gui.roomsens.value,
				gui.roomfreq.value,
				gui.roomdamp.value,
				gui.revlevel.value,
				gui.revtime.value,
				gui.revhf.value,
				gui.revlf.value,
				gui.dlylevel.value,
				gui.dlytime.value,
				gui.dlyfb.value
			];

			snaps = gui.snapshots.items;
		{
			sources.do{ arg src;
				if(src[\rotastate]){ src[\rota].stop; src[\rotastate] = false };
				if(src[\randstate]){ src[\rand].stop; src[\randstate] = false };
				src[\node].free;
				src[\node] = nil;
			};

			array = array.add(sources);
			array = array.add(fxparas);
			array = array.add(snaps);

			file.write(array.asCompileString);
			file.close;
		}.defer;


			sources.pairsDo{ arg key, src, i;
				srcon.value(key);
				if(src[\state] == false){ src[\node].set(\gate, 0) };
			};
		},
		cancelFunc: {"canceled".postln});

};

// ----- load a session
loadprj = { var array, file;
	{
		Dialog.openPanel({ arg paths;

			autorefreshview.stop;
			gui.src.enabled_(true);

			sources.keys.copy.do{ arg id; removesrc.value(id) };
			file = File(paths, "r");
			array = file.readAllString.interpret;
			{
				gui.roomsens.value = array[1][0];
				gui.roomfreq.value = array[1][1];
				gui.roomdamp.value = array[1][2];
				gui.revlevel.value = array[1][3];
				gui.revtime.value = array[1][4];
				gui.revhf.value = array[1][5];
				gui.revlf.value = array[1][6];
				gui.dlylevel.value = array[1][7];
				gui.dlytime.value = array[1][8];
				gui.dlyfb.value = array[1][9];

				roomsens = array[1][0];
				roomfreq = array[1][1];
				roomdamp = array[1][2];

				reverb.do{ arg it;
					it.set(\amp, gui.revlevel.value.dbamp,
						\rt, gui.revtime.value,
						\hfratio, gui.revhf.value,
						\lfratio, gui.revlf.value) };

				delay.do{ arg it;
					it.set(\amp, gui.dlylevel.value.dbamp,
						\dly, gui.dlytime.value,
						\fb, gui.dlyfb.value) };

				array[0].pairsDo{ arg key, dict, i;
					sources.add( key -> dict);
					srcon.value(key);
				};

				sources.pairsDo{ arg key, src, i;
					if(src[\state] == false){ src[\node].set(\gate, 0) };
					rect2pos.value(src[\id]);

				};

				selected = sources.keys.choose;
				editsrc.value(selected);

				gui.snapshots.items = array[2];

			}.defer;

			autorefreshview.start;
		},
		cancelFunc: {"canceled".postln});
	}.defer;
};

// ----- close session clear stuff
cleanup = {
	autorefreshview.stop;
	sources.do{ arg src;
		if(src[\rotastate]){src[\rota].stop};
		if(src[\randstate]){src[\rand].stop};
		src[\node].free;
	};
	//statsources.do{arg it; it.free};
	reverb.do{arg it; it.free};
	delay.do{arg it; it.free};
	testsig.free;
	tracklevel.free;
	master.free;
	masterbus.free;
	revbus.free;
	auxbus.free;
	dlybus.free;
	srcgroup.free;
	fxsgroup.free;
	mstrgroup.free;
	if(gui.meters.visible == true) {gui.meters.close};
	if(gui.fxpanel.visible == true) {gui.fxpanel.close};
	if(gui.snaplist.visible == true) {gui.snaplist.close};
};

// ----- open helpfile
gethelp = {
	var path = currpath ++ "/spacepan_help.txt";
	Document.open(path);
};


// ----- add synths to server
makeSynths = {

	SynthDef("spacepan", {
		arg inbus = 100,
		out = 0,
		delays = #[0,0,0,0,0,0,0], //always set this array to lspos size!
		amps = #[0,0,0,0,0,0,0], //always set this array to lspos size!
		dodelays = 0,
		distance = 0,
		//pan = #[0,0],
		room = 1,
		roomsens = 0.5,
		roomfreq = 8000,
		roomdamp = 0.5,
		fxdlycomp = 0.02,
		rev = 1,
		dly = 0,
		aux = 0,
		auxbus = 0,
		revbus = 0,
		dlybus = 0,
		amp = 0,
		gate = 1;

		var sig, dirlevel, fxlevel, fxsig, predly;

		sig = In.ar(inbus, 1) * amp;
		sig = sig * Linen.kr(gate, 0.1, 1, 0.1, doneAction: 0);
		distance = distance * room;
		dirlevel = distance.lincurve(roomsens, 1, 1, roomdamp, 1);
		fxlevel = distance.lincurve(roomsens, 1, 0, 1, 1);
		predly = distance.lincurve(roomsens, 1, 0.03, 0.003, 1);

		sig = LPF.ar(sig, distance.lincurve(roomsens, 1, 20000, roomfreq, 1));

		sig = DelayC.ar(sig, 0.2, dodelays * delays.lag(0.05) + (SampleDur.ir * 4));

		//fxsig = sig * (1-amps);
		sig = sig * amps.lag(0.05);

		Out.ar(out, sig * dirlevel);
		//Out.ar(revbus, Pan4.ar(DelayC.ar(fxsig, 0.1, predly), pan[0], pan[1], fxlevel * rev));
		Out.ar(dlybus, sig * fxlevel * dly);
		Out.ar(revbus, DelayC.ar(sig, 0.1, predly, fxlevel * rev));
	}).add;

	SynthDef("tracklevel", { arg inbus = 100;
		var sig = In.ar(inbus, 1);
		SendReply.kr(Impulse.kr(20), '/level',[Amplitude.kr(sig)]);
	}).add;

	SynthDef("master", { arg in, out, amp = 1, gate = 1;
		var sig = In.ar(in, lspos.size);
		sig = sig * Linen.kr(gate, 0.1, 1, 0.1, doneAction: 0);
		sig = Limiter.ar(sig, 0.9, 0.01);
		Out.ar(out, LeakDC.ar(sig, mul: amp));
	}).add;

	SynthDef("reverb", { arg in, out, room, damp, amp;
		var sig = In.ar(in, 1);
		sig = FreeVerb.ar(sig, 1.0, room, damp, amp);
		Out.ar(out, sig);
	}).add;

	SynthDef("delay", { arg in, out, dly, dcy, lpf, hpf, amp;
		var sig = In.ar(in, 1);
		sig = CombL.ar(sig, 1.0, dly, dcy,amp);
		sig = LPF.ar(HPF.ar(sig, hpf), lpf);
		Out.ar(out, sig);
	}).add;

	SynthDef("testsig", { arg out;
		var sig = Decay2.ar(Impulse.ar(0.25), 0.1, 1, PinkNoise.ar, Decay.ar(Impulse.ar(1), 0.3, SinOsc.ar(500))) ;
		Out.ar(out, sig);
	}).add;


};
)

//EOF

