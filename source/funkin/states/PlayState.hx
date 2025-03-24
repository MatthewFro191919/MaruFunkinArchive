package funkin.states;

#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.LuaUtils;
import psychlua.HScript;
#end

import funkin.objects.*;
import funkin.objects.note.*;
import funkin.objects.funkui.FunkBar;
import funkin.objects.FunkCamera.AngledCamera;

@:build(macros.GetSetBuilder.build(["notes", "unspawnNotes", "controlArray", "playerStrums", "opponentStrums", "grpNoteSplashes", "curSong", "generatedMusic", "skipStrumIntro", "inBotplay", "dadBotplay"], "notesGroup"))
@:build(macros.GetSetBuilder.buildGet(["strumLineNotes", "strumLineInitPos", "playerStrumsInitPos", "opponentStrumsInitPos"], "notesGroup"))
class PlayState extends MusicBeatState
{	
	public static var instance:PlayState;
	public static var clearCache:Bool = true;
	public static var clearCacheData:Null<CacheClearing> = null;

	public static var SONG:SongJson;
	public static var isStoryMode:Bool = false;
	public static var storyWeek:String = 'tutorial';
	public static var storyPlaylist:Array<String> = [];
	public static var curDifficulty:String = 'normal';
	public static var inChartEditor:Bool = false;
	public static var deathCounter:Int = 0;

	public static var curStage:String = '';
	public var stageData:StageJson;
	public var stage:Stage;
	public var stageGroup:TypedGroup<Stage>;

	public var dad:Character;
	public var gf:Character;
	public var boyfriend:Character;

	public var dadGroup:SpriteGroup;
	public var gfGroup:SpriteGroup;
	public var boyfriendGroup:SpriteGroup;

	private var camFollow:FlxObject;
	private var targetCamPos:FlxPoint;
	private static var prevCamFollow:FlxObject;

	private var curSectionData:Dynamic;

	public var notesGroup:NotesGroup;
	private var ratingGroup:RatingGroup;

	public var skipCountdown:Bool = false;
	public var camZooming:Bool = false;
	public var startingSong:Bool = false;

	public var gfSpeed:Int = 1;
	public var gfOpponent:Bool = false;

	public var combo:Int = 0;
	public var health(default, set):Float = 1;
	function set_health(value:Float) {
		healthBar.updateBar(value = FlxMath.bound(value, 0, 2));
		if (value == 0) if (validScore)
			openGameOverSubstate();
		return health = value;
	}

	public var noteCount:Int = 0;
	public var noteTotal:Float = 0;

	private var iconGroup:SpriteGroup;
	private var iconP1:HealthIcon;
	private var iconP2:HealthIcon;
	public var healthBar:FunkBar;

	public var camGame:AngledCamera;
	public var camHUD:FunkCamera;
	public var camOther:FunkCamera;

	public var songLength:Float = 0;
	public var songScore:Int = 0;
	public var songMisses:Int = 0;
	public var scoreTxt:FlxFunkText;
	var watermark:FunkinSprite;

	public static var campaignScore:Int = 0;

	public var defaultCamZoom:Float = 1.05;
	public var defaultCamSpeed:Float = 1;
	public var camFollowLerp:Float = 0.04;

	public static var seenCutscene:Bool = false;
	public var inCutscene:Bool = false;
	public var inDialogue:Bool = true;
	public var dialogueBox:DialogueBoxBase = null;

	// Discord RPC variables
	#if discord_rpc
	var iconRPC:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end
	inline function formatDiff() return CoolUtil.formatStringUpper(curDifficulty); // For discord rpc

	public var ghostTapEnabled:Bool = false;
	public var inPractice:Bool = false;
	private var validScore(default, null):Bool = true;
	
	public var pauseSubstate:PauseSubState;
	
	// Lua shit
	public static var instance:PlayState;
	#if LUA_ALLOWED public var luaArray:Array<FunkinLua> = []; #end

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	private var luaDebugGroup:FlxTypedGroup<psychlua.DebugLuaText>;
	#end

	override public function create():Void {
		instance = this;

		#if mobile MobileTouch.setLayout(NOTES); #end

		if (clearCache) CoolUtil.clearCache(clearCacheData)
		else {
			FlxG.bitmap.clearUnused();
			CoolUtil.gc();
		}

		clearCache = true;
		clearCacheData = null;

		inPractice = getPref('practice');
		validScore = !(getPref('botplay') || inPractice);
		if (getPref('ghost-tap-style') == "dad turn") {
			if (SONG.notes[0] != null)
				ghostTapEnabled = !SONG.notes[0].mustHitSection;
		} else ghostTapEnabled = getPref('ghost-tap-style') == "on";

		SkinUtil.initSkinData();
		NoteUtil.initTypes();
		EventUtil.initEvents();
		CoolUtil.stopMusic();
		
		camGame = new AngledCamera();
		camHUD = new FunkCamera();
		camOther = new FunkCamera();
		camGame.bgColor = FlxColor.BLACK; camHUD.bgColor.alpha = camOther.bgColor.alpha = 0;
		FlxG.mouse.visible = false;
		
		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		FlxG.cameras.setDefaultDrawTarget(camGame, true);
		persistentUpdate = persistentDraw = true;

		#if discord_rpc
		detailsText = isStoryMode ? 'Story Mode: ${storyWeek.toUpperCase()}' : 'Freeplay';
		detailsPausedText = 'Paused - $detailsText';
		if (Character.getCharData(SONG.players[1]) != null)
			iconRPC = Character.getCharData(SONG.players[1]).icon;

		DiscordClient.changePresence(detailsText, '${SONG.song} (${formatDiff()})', iconRPC);
		#end

		// MAKE CHARACTERS
		gfGroup = new SpriteGroup();
		dadGroup = new SpriteGroup();
		boyfriendGroup = new SpriteGroup();

		gf = new Character(0, 0, SONG.players[2]);
		dad = new Character(0, 0, SONG.players[1]);
		boyfriend = new Character(0, 0, SONG.players[0], true);

		gf.group = gfGroup;
		dad.group = dadGroup;
		boyfriend.group = boyfriendGroup;

		// CACHE GAMEOVER STUFF
		GameOverSubstate.cacheSounds();

		// GET THE STAGE JSON SHIT
		curStage = SONG.stage;
		stageData = Stage.getJson(curStage);
		
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		luaDebugGroup = new FlxTypedGroup<psychlua.DebugLuaText>();
		luaDebugGroup.cameras = [camOther];
		add(luaDebugGroup);
		#end

		defaultCamZoom = stageData.zoom;
		Paths.currentLevel = stageData.library;
		SkinUtil.setCurSkin(stageData.skin);
		
		/*
						LOAD SCRIPTS
			Still a work in progress!!! Can be improved
		*/
		ModdingUtil.clearScripts(); //Clear any scripts left over

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// STAGE SCRIPTS
		#if LUA_ALLOWED startLuasNamed('stages/' + curStage + '.lua'); #end
		#if HSCRIPT_ALLOWED startHScriptsNamed('stages/' + curStage + '.hx'); #end

		// CHARACTER SCRIPTS
		if(gf != null) startCharacterScripts(gf.curCharacter);
		startCharacterScripts(dad.curCharacter);
		startCharacterScripts(boyfriend.curCharacter);
		#end

		stageGroup = new TypedGroup<Stage>();
		stageGroup.add(stage);
		add(stageGroup);

		if (cript != null)
			cript.set("ScriptStage", stage);
		
		// Set stage character positions
		gfOpponent = (SONG.players[1] == SONG.players[2]) && dad.isGF;
		stage.setupPlayState(this, true);

		iconGroup = new SpriteGroup();
		iconP1 = new HealthIcon(boyfriend.icon, true, true);
		iconP2 = new HealthIcon(dad.icon, false, true);
		dad.iconSpr = iconP2;
		boyfriend.iconSpr = iconP1;

		//Character Scripts
		boyfriend.type = BF; dad.type = DAD; gf.type = GF;
		addCharScript(boyfriend); addCharScript(dad); addCharScript(gf);

		//Song Scripts
		ModdingUtil.addScriptFolder('songs/${Song.formatSongFolder(SONG.song)}');

		//Skin Script
		ModdingUtil.addScript(Paths.script('skins/${SkinUtil.curSkin}'));

		//Global Scripts
		ModdingUtil.addScriptFolder('data/scripts/global');

		notesGroup = new NotesGroup(SONG);

		targetLayer = stage.getLayer("bg");
		ModdingUtil.addCall('create');
		targetLayer = null;

		add(notesGroup);
		notesGroup.init();

		// Set character groups
		gfGroup.add(gf);
		dadGroup.add(dad);
		boyfriendGroup.add(boyfriend);

		//Cam Follow
		if (prevCamFollow != null) {
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		else {
			camFollow = new FlxObject(0, 0, 1, 1);
			camFollow.setPosition(-stageData.startCamOffsets[0], -stageData.startCamOffsets[1]);
			camFollow.active = false;
		}
		add(camFollow);

		targetCamPos = FlxPoint.get();
		camFollowLerp = 0.04 * defaultCamSpeed;
		camGame.follow(camFollow, LOCKON, camFollowLerp);
		camGame.zoom = defaultCamZoom;
		snapCamera();

		healthBar = new FunkBar(0, !getPref('downscroll') ? FlxG.height * 0.9 : FlxG.height * 0.1, SkinUtil.getAssetKey("healthBar"));
		healthBar.screenCenter(X);
		add(healthBar);

		add(iconGroup);
		iconGroup.add(iconP1); iconGroup.add(iconP2);
		healthBar.drawComplex(camGame); iconGroup.update(0.0); // Move the icons to the healthbar

		scoreTxt = new FlxFunkText(0, healthBar.y + 30, "", FlxPoint.weak(FlxG.width, 20));
		add(scoreTxt);

		if (getPref('vanilla-ui')) {
			scoreTxt.setPosition(healthBar.x + healthBar.width - 190, healthBar.y + 30);
			scoreTxt.style = TextStyle.OUTLINE(1, 6, FlxColor.BLACK);
		}
		else {
			scoreTxt.size = 20;
			scoreTxt.style = TextStyle.OUTLINE(2, 6, FlxColor.BLACK);
			scoreTxt.alignment = "center";
		}

		ratingGroup = new RatingGroup(boyfriend);
		add(ratingGroup);
		updateScore();

		watermark = new FunkinSprite(SkinUtil.getAssetKey("watermark"), [FlxG.width, getPref('downscroll') ? 0 : FlxG.height], [0,0]);
		for (i in ['botplay', 'practice']) watermark.addAnim(i, i.toUpperCase(), 24, true);
		watermark.playAnim(notesGroup.inBotplay ? 'botplay' : 'practice');
		watermark.setScale(SkinUtil.curSkinData.scale * 0.7);
		watermark.x -= watermark.width * 1.2; watermark.y -= watermark.height * (getPref('downscroll') ? -0.2 : 1.2);
		watermark.alpha = validScore ? 0 : 0.8;
		add(watermark);

		// Set objects to HUD cam
		for (i in [notesGroup,  healthBar, iconGroup, scoreTxt, watermark])
			i.camera = camHUD;

		startingSong = true;
		ModdingUtil.addCall('createPost');
		inCutscene ? ModdingUtil.addCallBasic('startCutscene', false) : startCountdown();

		super.create();
		destroySubStates = false;
		pauseSubstate = new PauseSubState();
		
		CoolUtil.gc(true);
	}


	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [LuaUtils.Function_Continue];

		var arr:Array<FunkinLua> = [];
		for (script in luaArray)
		{
			if(script.closed)
			{
				arr.push(script);
				continue;
			}

			if(exclusions.contains(script.scriptName))
				continue;

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == LuaUtils.Function_StopLua || myValue == LuaUtils.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}

			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(script.closed) arr.push(script);
		}

		if(arr.length > 0)
			for (script in arr)
				luaArray.remove(script);
		#end
		return returnVal;
	}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String)
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getSharedPath(luaFile);

		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getSharedPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if(script.scriptName == luaToLoad) return false;

			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end

	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String)
	{
		#if MODS_ALLOWED
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if(!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getSharedPath(scriptFile);
		#else
		var scriptToLoad:String = Paths.getSharedPath(scriptFile);
		#end

		if(FileSystem.exists(scriptToLoad))
		{
			if (Iris.instances.exists(scriptToLoad)) return false;

			initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	public function addTextToDebug(text:String, color:FlxColor) {
		var newText:psychlua.DebugLuaText = luaDebugGroup.recycle(psychlua.DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:psychlua.DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);

		Sys.println(text);
	}
	#end

	public var video:FunkVideo;

	public function startVideo(file:String, ?completeFunc:()->Void):FunkVideo {
		video = new FunkVideo();
		video.load(Paths.video(file));
		video.onComplete = completeFunc ?? startCountdown;
		video.play();

		return video;
	}

	public function endVideo():Void {
		if (video != null) {
			video.endVideo();
			video = null;
		}
	}

	public var openDialogueFunc:()->Void;

	function createDialogue():Void {
		showUI(false);
		ModdingUtil.addCall('createDialogue'); // Setup dialogue box
		ModdingUtil.addCall('postCreateDialogue'); // Setup transitions

		// Default transition
		if (openDialogueFunc == null) {
			var black = new FlxSpriteExt(-100, -100).makeRect(FlxG.width * 2, FlxG.height * 2, FlxColor.BLACK);
			black.scrollFactor.set();
			add(black);

			FlxTween.tween(black, {alpha: 0}, black.alpha > 0 ? 1.5 : 0.000001, {ease: FlxEase.circOut,
				onComplete: function(twn:FlxTween) {
					quickDialogueBox();
					remove(black, true);
					black.destroy();
			}});
		}
		else openDialogueFunc();
	}

	public function quickDialogueBox():Void {
		if (dialogueBox == null) {
			dialogueBox = switch (SkinUtil.curSkin) {
				case 'pixel':	new PixelDialogueBox();
				default:		new NormalDialogueBox();
			}
		}

		dialogueBox.closeCallback = startCountdown;
		dialogueBox.camera = camHUD;
		add(dialogueBox);
	}

	public var startTimer:FlxTimer;

	function startCountdown():Void {
		showUI(true);
		inCutscene = inDialogue = false;
		startedCountdown = seenCutscene = true;

		if (!notesGroup.skipStrumIntro) {
			notesGroup.opponentStrums.introStrums();
			notesGroup.playerStrums.introStrums();
		}

		Conductor.songPosition = -Conductor.crochet * 5;
		Conductor.setPitch(Conductor.songPitch);
		
		curSectionData = SONG.notes[0];
		cameraMovement();

		if (skipCountdown) {
			Conductor.songPosition = 0;
			return;
		}

		ModdingUtil.addCall('startCountdown');

		// Cache countdown assets
		final countdownSounds:Array<FlxSoundAsset> = [];
		final countdownImages:Array<FlxGraphicAsset> = [];

		"intro3,intro2,intro1,introGo".split(",").fastForEach((key, i) -> {
			final key = SkinUtil.getAssetKey(key, SOUND);
			countdownSounds.push(Paths.sound(key));
		});

		"ready,set,go".split(",").fastForEach((key, i) -> {
			var key:String = SkinUtil.getAssetKey(key, IMAGE);
			var lod:Int = LodLevel.resolve(SkinUtil.curSkinData.allowLod ?? true);
			countdownImages.push(Paths.image(key, null, null, null, lod));
		});

		var swagCounter:Int = 0;

		startTimer = new FlxTimer().start(Conductor.crochetMills, (tmr) ->
		{
			beatCharacters();
			ModdingUtil.addCallBasic('startTimer', swagCounter);

			if (swagCounter > 0) {
				final countdownSpr:FunkinSprite = new FunkinSprite(countdownImages[swagCounter-1]);
				countdownSpr.setScale(SkinUtil.curSkinData.scale);
				countdownSpr.screenCenter();
				countdownSpr.camera = camHUD;
				add(countdownSpr);

				countdownSpr.acceleration.y = SONG.bpm*60;
				countdownSpr.velocity.y -= SONG.bpm*10;
				FlxTween.tween(countdownSpr, {alpha: 0}, Conductor.crochetMills, {ease: FlxEase.cubeInOut, onComplete: function(twn:FlxTween) countdownSpr.destroy()});
			}

			CoolUtil.playSound(countdownSounds[swagCounter], 0.6);
			swagCounter++;
		}, 4);
	}

	public function startSong():Void {
		camZooming = true;
		startingSong = false;
		CoolUtil.stopMusic();
		startTimer = FlxDestroyUtil.destroy(startTimer);

		ModdingUtil.addCall('startSong');

		Conductor.volume = 1;
		Conductor.setPitch(Conductor.songPitch);
		Conductor.sync();
		Conductor.play();

		#if html5
		// Dont know, dont ask
		FlxG.signals.preUpdate.addOnce(() -> {
			Conductor.pause();
			Conductor.setPitch(Conductor.songPitch);
			Conductor.sync();
			Conductor.play();
		});
		#end

		// Song duration in a float, useful for the time left feature
		songLength = Conductor.inst.length;

		#if discord_rpc DiscordClient.changePresence(detailsText, '${SONG.song} (${formatDiff()})', iconRPC, true, songLength); #end
	}

	private function openPauseSubState(easterEgg:Bool = false):Void {
		if (!paused) {
			if (ModdingUtil.getCall("openPauseSubState")) return;
			paused = true;
			persistentUpdate = false;
			persistentDraw = true;
			camGame.followLerp = 0;
			if (!startingSong)
				Conductor.pause();
			
			CoolUtil.setGlobalManager(false);
			CoolUtil.pauseSounds();

			camGame.updateFX = camHUD.updateFX = camOther.updateFX = false;
	
			pauseSubstate.init();
			openSubState((easterEgg && FlxG.random.bool(0.1)) ? new funkin.substates.GitarooPauseSubState() : pauseSubstate);
		}
	}

	override function openSubState(SubState:FlxSubState):Void {
		Conductor.setPitch(1, false);
		super.openSubState(SubState);
	}

	override function closeSubState():Void {
		if (paused) {
			paused = false;
			camGame.followLerp = camFollowLerp;
			camGame.updateFX = camHUD.updateFX = camOther.updateFX = true;
			persistentUpdate = true;
			CoolUtil.setGlobalManager(true);

			if (!startingSong) {
				Conductor.setPitch(Conductor.songPitch);
				Conductor.sync();
				Conductor.play();
			}

			#if discord_rpc
			var presenceDetails = '${SONG.song} (${formatDiff()})';
			var presenceTime = songLength - Conductor.songPosition;
			DiscordClient.changePresence(detailsText, presenceDetails, iconRPC, Conductor.songPosition >= 0, presenceTime);
			#end
		}
		super.closeSubState();
	}

	public var paused:Bool = false;
	public var startedCountdown:Bool = false;
	var canPause:Bool = true;
	var canDebug:Bool = true;

	public function updateScore():Void {
		var songAccuracy:Null<Float> = (noteCount > 0) ? 0 : null;
		var songRating:String = '?';

		if (noteCount > 0) {
			songAccuracy = (noteTotal/noteCount)*100;
			songAccuracy = FlxMath.roundDecimal(songAccuracy, 2);
			songRating = Highscore.getAccuracyRating(songAccuracy).toUpperCase();
		}

		scoreTxt.text = notesGroup.vanillaUI ?
		'Score:$songScore' :
		'Score: $songScore / Accuracy: ${(noteCount > 0) ? '$songAccuracy%' : ''} [$songRating] / Misses: $songMisses';

		ModdingUtil.addCall('updateScore', [songScore, songMisses, songAccuracy, songRating]);
	}

	var oldIconID:Int = 0; // Old icon easter egg
	public var allowIconEasterEgg:Bool = true;
	inline function changeOldIcon() {
		switch (oldIconID = FlxMath.wrap(oldIconID + 1, 0, 2)) {
			default: 	iconP1.makeIcon(boyfriend.icon); 	iconP2.makeIcon(dad.icon);
			case 1: 	iconP1.makeIcon('bf-old'); 			iconP2.makeIcon('dad');
			case 2: 	iconP1.makeIcon('bf-older'); 		iconP2.makeIcon('dad-older');
		}
	}

	override public function update(elapsed:Float):Void {
		__superUpdate(elapsed);
		ModdingUtil.addCallBasic('update', elapsed);

		if (canDebug) {
			final justPressed = FlxG.keys.justPressed;
			
			if (canPause) {
				if (startedCountdown) if (getKey('PAUSE', JUST_PRESSED)) {
					openPauseSubState(true);
					#if discord_rpc DiscordClient.changePresence(detailsPausedText, '${SONG.song} (${formatDiff()})', iconRPC); #end
				}
			}

			if (allowIconEasterEgg) if (justPressed.NINE)
				changeOldIcon();

			if (justPressed.ONE) if (CoolUtil.debugMode)
				endSong();

			#if DEV_TOOLS
			if (justPressed.SIX) {
				clearCacheData = {tempCache: false};
				#if discord_rpc DiscordClient.changePresence("Stage Editor", null, null, true); #end
				switchState(new StageDebug(stageData));
			}

			if (justPressed.SEVEN) {
				clearCacheData = {tempCache: false};
				switchState(new ChartingState());
				#if discord_rpc DiscordClient.changePresence("Chart Editor", null, null, true); #end
			}

			if (justPressed.EIGHT) {
				clearCacheData = {tempCache: false};
				#if discord_rpc DiscordClient.changePresence("Character Editor", null, null, true); #end
	
				if (FlxG.keys.pressed.SHIFT) {
					if (FlxG.keys.pressed.CONTROL) switchState(new AnimationDebug(SONG.players[2]));
					else switchState(new AnimationDebug(SONG.players[0]));
				}
				else switchState(new AnimationDebug(SONG.players[1]));
			}
			#end
		}

		//End the song if the conductor time is the same as the length
		if (Conductor.songPosition >= songLength && canPause)
			endSong();

		if (camZooming) {
			camGame.zoom = CoolUtil.coolLerp(camGame.zoom, defaultCamZoom, 0.05);
			camHUD.zoom = CoolUtil.coolLerp(camHUD.zoom, 1, 0.05);
		}

		// RESET -> Quick Game Over Screen
		if (!inCutscene) if (canDebug) if (getKey('RESET', JUST_PRESSED))
			health = 0;

		ModdingUtil.addCallBasic('updatePost', elapsed);
	}

	public function openGameOverSubstate():Void
	{
		if (ModdingUtil.getCall("openGameOverSubstate"))
			return;
		
		camGame.clearFX(); camHUD.clearFX(); camOther.clearFX();
		persistentUpdate = persistentDraw = false;
		paused = true;

		deathCounter++;
		Conductor.stop();
		openSubState(new GameOverSubstate(boyfriend.OG_X, boyfriend.OG_Y));

		// Game Over doesn't get his own variable because it's only used here
		#if discord_rpc DiscordClient.changePresence('Game Over - $detailsText', SONG.song + ' (${formatDiff()})', iconRPC); #end
	}

	inline public function snapCamera():Void
		camGame.focusOn(camFollow.getPosition());

	public var camMove:Bool = true;
	
	public function cameraMovement():Void {
		if (camMove) if (notesGroup.generatedMusic) if (curSectionData != null) {
			var camBf:Bool = curSectionData.mustHitSection;
			camBf ? boyfriend.prepareCamPoint(targetCamPos, stageData.camBounds) :
					dad.prepareCamPoint(targetCamPos, stageData.camBounds);

			if (camFollow.x != targetCamPos.x || camFollow.y != targetCamPos.y) {
				camFollow.setPosition(targetCamPos.x, targetCamPos.y);
				ModdingUtil.addCall('cameraMovement', [camBf ? 1 : 0, targetCamPos]);
			}
		}
	}

	function endSong():Void {
		canPause = false;
		deathCounter = 0;
		Conductor.volume = 0;
		ModdingUtil.addCall('endSong');
		if (validScore)
			Highscore.saveSongScore(SONG.song, curDifficulty, songScore);

		#if DEV_TOOLS
		if (inChartEditor) {
			switchState(new ChartingState());
			#if discord_rpc DiscordClient.changePresence("Chart Editor", null, null, true); #end
		}
		else #end inCutscene ? ModdingUtil.addCallBasic('startCutscene', true) : exitSong();
	}

	public function exitSong():Void {
		if (isStoryMode) {
			campaignScore += songScore;
			storyPlaylist.removeAt(0);
			storyPlaylist.length <= 0 ? endWeek() : switchSong();
		}
		else {
			ModdingUtil.addCall('exitFreeplay');

			clearCache = true;
			switchState(new FreeplayState());
		}
	}

	public function endWeek():Void
	{
		if (validScore) {
			Highscore.saveWeekScore(storyWeek, curDifficulty, campaignScore);
			final weekData = WeekSetup.weekMap.get(storyWeek)?.data ?? null;
			if (weekData != null) if (WeekSetup.weekMap.exists(weekData.unlockWeek)) if (!Highscore.getWeekUnlock(weekData.unlockWeek))
			{
				Highscore.setWeekUnlock(weekData.unlockWeek, true);
				StoryMenuState.unlockWeek = WeekSetup.weekMap.get(weekData.unlockWeek); // Setup the unlock week animation
			}
		}

		ModdingUtil.addCall('endWeek');

		clearCache = true;
		switchState(new StoryMenuState());
	}

	function switchSong():Void {
		final nextSong:String = PlayState.storyPlaylist[0];
		trace('LOADING NEXT SONG [$nextSong-$curDifficulty]');

		PlayState.SONG = Song.loadFromFile(curDifficulty, nextSong);
		Conductor.stop();

		// Reset cam follow and enable transition if the stage changed
		final changedStage:Bool = (SONG.stage != curStage);
		prevCamFollow = changedStage ? null : camFollow;
		seenCutscene = false;

		clearCache = true;
		clearCacheData = {tempCache: false, skins: false}
		ModdingUtil.addCall('switchSong', [nextSong, curDifficulty]); // Could be used to change cache clear
		
		// If the stage has changed we can sneak in a lil loading screen :]
		changedStage ? 	WeekSetup.loadPlayState(new PlayState(), false, false)
		: 				switchState(new PlayState(), true);
	}

	override function startTransition() {
		canDebug = canPause = false;
		super.startTransition();
	}

	public function popUpScore(strumtime:Float, daNote:Note) {
		combo++;
		noteCount++;
		ModdingUtil.addCallBasic('popUpScore', daNote);

		final noteRating:String = CoolUtil.getNoteJudgement(CoolUtil.getNoteDiff(daNote));
		final rating = Highscore.ratingMap.get(noteRating);
		
		songScore = (songScore + rating.score);
		noteTotal = (noteTotal + rating.noteGain);
		if (ghostTapEnabled) health = (health - rating.ghostLoss);

		if (!getPref('stack-rating'))
			ratingGroup.clearGroup();
		
		ratingGroup.drawComplete(noteRating, combo);
		updateScore();

		return noteRating;
	}

	override function stepHit(curStep:Int):Void {
		super.stepHit(curStep);
		Conductor.autoSync();
		ModdingUtil.addCallBasic('stepHit', curStep);
	}

	inline function beatCharacters() {
		iconP1.bumpIcon(); 			iconP2.bumpIcon();
		boyfriend.danceInBeat(); 	dad.danceInBeat();
		if (curBeat % gfSpeed == 0) gf.danceInBeat();
	}

	override public function beatHit(curBeat:Int):Void
	{
		super.beatHit(curBeat);
		beatCharacters();
		ModdingUtil.addCallBasic('beatHit', curBeat);
	}

	override public function sectionHit(curSection:Int):Void
	{
		super.sectionHit(curSection);
		if (Conductor.songPosition <= 0)
			curSection = 0;
		
		curSectionData = SONG.notes[curSection];
		cameraMovement();

		if (camZooming) if (getPref('camera-zoom')) {
			camGame.zoom += 0.015;
			camHUD.zoom += 0.03;
		}

		if (curSectionData != null) {
			if (curSectionData.changeBPM) if (curSectionData.bpm != Conductor.bpm)
				Conductor.bpm = curSectionData.bpm;

			if (getPref('ghost-tap-style') == "dad turn")
				ghostTapEnabled = !curSectionData.mustHitSection;
		}

		ModdingUtil.addCallBasic('sectionHit', curSection);
	}

	override function destroy():Void
	{
		Conductor.setPitch(1, false);
		Conductor.stop();
		CoolUtil.destroyMusic();
		SkinUtil.setCurSkin('default');
		
		endVideo();

		ModdingUtil.addCall('destroy');

		FlxG.camera.bgColor = FlxColor.BLACK;
		
		targetCamPos = FlxDestroyUtil.put(targetCamPos);
		if (clearCache) CoolUtil.clearCache(clearCacheData);
		instance = null;
		super.destroy();
	}

	inline function addCharScript(char:Character) {
		final script = ModdingUtil.addScript(Paths.script('characters/' + char.curCharacter), '_charScript_' + char.type);
		if (script != null) {
			char.script = script;
			script.set('ScriptChar', char);
			script.safeCall('createChar', [char]);
		}
	}

	public function switchChar(type:String, newCharName:String):Void
	{
		final targetChar:Character = switch(type = type.toLowerCase().trim()) {
			case 'dad': dad;
			case 'gf' | 'girlfriend': gf;
			default: boyfriend;
		}

		if (targetChar.curCharacter == newCharName) // Is already that character
			return;

		final newChar:Character = new Character(0, 0, newCharName,targetChar.isPlayer).copyStatusFrom(targetChar);
		if (targetChar.iconSpr != null) targetChar.iconSpr.makeIcon(newChar.icon);
		
		// Clear character group
		final group = targetChar.group;
		targetChar.callScript("destroyChar", [targetChar, newChar, newCharName]);
		group.members.fastForEach((object, i) -> object.destroy());

		// Character script
		group.clear();
		group.add(newChar);
		addCharScript(newChar);

		switch (type) {
			case 'dad': dad = newChar; notesGroup.dad = newChar;
			case 'girlfriend' | 'gf': gf = newChar;
			default: boyfriend = newChar; notesGroup.boyfriend = newChar;
		}
		
		cameraMovement();
	}

	public function showUI(bool:Bool):Void {
		#if mobile MobileTouch.setLayout(bool ? NOTES : NONE); #end
		
		final displayObjects:Array<FlxBasic> = [iconGroup, scoreTxt, healthBar, notesGroup, watermark];
		displayObjects.fastForEach((object, i) -> object.visible = bool);
	}

	// Some quick shortcuts

	public var playerStrumNotes(get,never):Array<NoteStrum>; inline function get_playerStrumNotes() return notesGroup.playerStrums.members;
	public var opponentStrumNotes(get,never):Array<NoteStrum>; inline function get_opponentStrumNotes() return notesGroup.opponentStrums.members;
	public var objMap(get, never):Map<String, FlxObject>; inline function get_objMap() return stage.objects;

	public var songSpeed(get,never):Float; inline function get_songSpeed() return NotesGroup.songSpeed;
	public var inst(get, never):FlxFunkSound; inline function get_inst() return Conductor.inst;
	public var vocals(get, never):FlxFunkSound; inline function get_vocals() return Conductor.vocals;
	public var backup(get, never):FlxFunkSound; inline function get_backup() return Conductor.backup;
}
